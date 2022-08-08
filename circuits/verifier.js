
require("dotenv").config();
const { execSync } = require("child_process");
const fs = require("fs");
const snarkjs = require("snarkjs");
const ejs = require("ejs");

function capitalizeFirstLetter(string) {
  return string.charAt(0).toUpperCase() + string.slice(1);
}

if (process.argv.length !== 5) {
  console.log("usage");
  console.log(
    "verifier comma,seperated,list,of,circuits input_file expectation[true/false]"
  );
  process.exit(1);
}

async function run() {
  const logger = {
    debug: () => { },
    info: console.log,
    warn: console.log,
    error: console.log,
  };

    const name = process.argv[2];
    const input_name = process.argv[3];
    const expectation = process.argv[4] === "true";
    const final_zkey = fs.readFileSync("./artifacts/" + name + ".zkey");

    process.chdir("./" + name + "/circuit_cpp");

    var start = Date.now();

    execSync("wget --no-check-certificate https://github.com/nlohmann/json/releases/download/v3.10.5/json.hpp && mkdir -p nlohmann && mv json.hpp nlohmann", {
      stdio: "ignore",
    }
    );

    execSync("make", {
      stdio: "inherit",
    });

    try {
      execSync("./circuit ../" + input_name + " witness.wtns", {
        stdio: "inherit",
      }
      );
    } catch (err) {
      var v = false;
      console.log("Verified? " + v);
      if (v != expectation) throw new Error("Did not meet expectation");
      process.exit(0);
    }
    const wtns = fs.readFileSync("witness.wtns");

    console.log("Witness generation took " + (Date.now() - start) / 1000 + " s");

    process.chdir("../../");
    
    console.log('Proving:');

    start = Date.now();
    const { proof, publicSignals } = await snarkjs.groth16.prove(final_zkey, wtns, logger);
    console.log("Proof took " + (Date.now() - start) / 1000 + " s");

    const verification_key = await snarkjs.zKey.exportVerificationKey(final_zkey);
    console.log(verification_key)

    console.log('Verifying:');
    const verified = await snarkjs.groth16.verify(verification_key, publicSignals, proof, logger);
    console.log("Verified? " + verified);
    console.log("Verification took " + (Date.now() - start) / 1000 + " s");
    if (verified != expectation) throw new Error("Did not meet expectation");
    console.log("Done!")

    a = [proof.pi_a[0], proof.pi_a[1]];
    b = [[proof.pi_b[0][1], proof.pi_b[0][0]], [proof.pi_b[1][1], proof.pi_b[1][0]]]
    c = [proof.pi_c[0], proof.pi_c[1]];

    console.log(input_name);
    var add;
    if (verified) {
      add = "";
    }
    else {
      add = "_incorrect";
    }
    console.log(add);

    fs.writeFileSync(
      './'+name+'/public'+add+'.json',
      JSON.stringify(publicSignals, null, 2),
      () => {},
    );

    fs.writeFileSync(
      './'+name+'/private'+add+'.json',
      JSON.stringify({a:a,b:b,c:c}, null, 2),
      () => {},
    );

    if (verified) {
      var groth16_template = await fs.promises.readFile("./templates/verifier_groth16.sol.ejs", "utf8");
      var store_template = await fs.promises.readFile("./templates/store.sol.ejs", "utf8");
      const zkey_path = "./artifacts/"+name+".zkey";
      
      var vkey = await snarkjs.zKey.exportVerificationKey(zkey_path, logger);
      vkey.name = capitalizeFirstLetter(name)

      var groth16_verifier = ejs.render(groth16_template, vkey)
      var verifying_key_store = ejs.render(store_template, vkey)
      fs.writeFileSync("../hardhat/contracts/" + capitalizeFirstLetter(name) + "Verifier.sol", groth16_verifier);
      fs.writeFileSync("../hardhat/contracts/" + capitalizeFirstLetter(name) + "VKStore.sol", verifying_key_store);
    }

}

run()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });