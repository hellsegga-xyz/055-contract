
require("dotenv").config();
const { execSync } = require("child_process");
const fs = require("fs");
const snarkjs = require("snarkjs");
const ejs = require("ejs");
const circuitsList = process.argv[2];
const deterministic = process.argv[3] === "true";

if (process.argv.length !== 4) {
  console.log("usage");
  console.log(
    "builder comma,seperated,list,of,circuits [`true` if deterministic / `false` if not]"
  );
  process.exit(1);
}

const snakeToCamel = (str) =>
  str.replace(/([-_][a-z])/g, (group) => group.toUpperCase().replace("-", "").replace("_", ""));

async function run() {
  const logger = {
    debug: () => { },
    info: console.log,
    warn: console.log,
    error: console.log,
  };

  const cwd = process.cwd();

  for (circuitName of circuitsList.split(",")) {
    console.log("> Compiling " + circuitName);
    if (deterministic && !process.env[circuitName.toUpperCase() + "_BEACON"]) {
      console.log("ERROR! you probably dont have an .env file");
      process.exit(1);
    }

    process.chdir(cwd + "/" + circuitName);

    const newKey = { type: "mem" };
    const final_zkey = { type: "mem" };

    const data = JSON.parse(fs.readFileSync("../sample.json"));

    var template = fs.readFileSync('circuit.circom.ejs', 'utf-8');
    var circuit = ejs.render(template, {mint_params: [data.s_a, data.s_b, data.channels, data.pack, data.pack2],
                                        reveal_params: [data.s_a, data.channels, data.packed_len],
                                        secret_key: data.secret_key,
                                       });

    fs.writeFileSync(   
      "circuit.circom",
      circuit
    );

    var start = Date.now();
    console.log("Compiling ...");
    execSync("~/.cargo/bin/circom circuit.circom --r1cs --wasm --c", {
      stdio: "inherit",
    });
    console.log("Compilation took " + (Date.now() - start) / 1000 + " s");

    const r1cs = fs.readFileSync("./circuit.r1cs");

    const ptau = cwd + "/ptau/" + fs.readdirSync(cwd + "/ptau/").filter((fn) => fn.endsWith(".ptau"))[0];
    console.log("Using ptau: " + ptau);

    const _cir = await snarkjs.r1cs.info(r1cs, logger);

    console.log("Instantiating new zKey ...");
    start = Date.now();
    const _csHash = await snarkjs.zKey.newZKey(r1cs, ptau, newKey, logger);
    console.log("Instantiation took " + (Date.now() - start) / 1000 + " s");

    console.log("Contributing ...");
    start = Date.now();
    const _contributionHash = deterministic
      ? await snarkjs.zKey.beacon(
        newKey,
        final_zkey,
        undefined,
        process.env[circuitName.toUpperCase() + "_BEACON"],
        10,
        logger
      )
      : await snarkjs.zKey.contribute(newKey, final_zkey, undefined, `${Date.now()}`, logger);

    console.log("Contribution took " + (Date.now() - start) / 1000 + " s");
    
    fs.writeFileSync(
      cwd + "/artifacts/" + snakeToCamel(circuitName) + ".zkey",
      final_zkey.data
    );
      
  }
}

run()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });