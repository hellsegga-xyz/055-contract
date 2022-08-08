//
// Copyright 2017 Christian Reitwiessner
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//
// 2019 OKIMS
//      ported to solidity 0.6
//      fixed linter warnings
//      added requiere error messages
//
// 2022 hellsegga
//      compatibility with newer solidity version
//      gas optimization
//
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
import {RevealVKStore} from "./RevealVKStore.sol";
import "./Pairing.sol";

contract RevealVerifier {
    using Pairing for *;
    address public VKStore;
    constructor(address addr) {
        VKStore = addr;
    }
    struct VerifyingKey {
        Pairing.G1Point alfa1;
        Pairing.G2Point beta2;
        Pairing.G2Point gamma2;
        Pairing.G2Point delta2;
        //Pairing.G1Point[] IC;
    }
    struct Proof {
        Pairing.G1Point A;
        Pairing.G2Point B;
        Pairing.G1Point C;
    }
    function verifyingKey() internal pure returns (VerifyingKey memory vk) {
        vk.alfa1 = Pairing.G1Point(
            20491192805390485299153009773594534940189261866228447918068658471970481763042,
            9383485363053290200918347156157836566562967994039712273449902621266178545958
        );

        vk.beta2 = Pairing.G2Point(
            [4252822878758300859123897981450591353533073413197771768651442665752259397132,
             6375614351688725206403948262868962793625744043794305715222011528459656738731],
            [21847035105528745403288232691147584728191162732299865338377159692350059136679,
             10505242626370262277552901082094356697409835680220590971873171140371331206856]
        );
        vk.gamma2 = Pairing.G2Point(
            [11559732032986387107991004021392285783925812861821192530917403151452391805634,
             10857046999023057135944570762232829481370756359578518086990519993285655852781],
            [4082367875863433681332203403145435568316851327593401208105741076214120093531,
             8495653923123431417604973247489272438418190587263600148770280649306958101930]
        );
        vk.delta2 = Pairing.G2Point(
            [7097300879054166716055313759130380865711283338477787465191462477077205389753,
             7866334169760910528995916305968143354836260704522459552724323544370340705674],
            [364452281174209557735571930469749548733765047770352954344227176359158182713,
             20506793826798048908578502105076444809849153868799340282859422623583425596580]
        );
    }

    /// @return r  bool true if proof is valid
    function verifyProof(
            uint[2] calldata a,
            uint[4] calldata b,
            uint[2] calldata c,
            uint[293] calldata input
        ) external view returns (bool r) {
       
        // Negate proofA first
        Pairing.G1Point memory proofA;
        if (a[0] == 0 && a[1] == 0) {
            proofA = Pairing.G1Point(0, 0);
        } else {
            proofA = Pairing.G1Point(a[0], Pairing.PRIME_Q - (a[1] % Pairing.PRIME_Q));
        }
        Pairing.G2Point memory proofB = Pairing.G2Point([b[0], b[1]], [b[2], b[3]]);
        Pairing.G1Point memory proofC = Pairing.G1Point(c[0], c[1]);
        
        VerifyingKey memory vk = verifyingKey();
        uint256 [588] memory vkIC = RevealVKStore(VKStore).verifyingKey();
        require( (input.length + 1) * 2 == vkIC.length,"verifier-bad-input");
        
        uint256[3] memory ip3;
        uint256[4] memory ip4;
        bool success;

        for (uint i = 0; i < input.length; i++) {
            require(input[i] < Pairing.SNARK_SCALAR_FIELD,"verifier-gte-snark-scalar-field");
            
            ip3[0] = vkIC[(i + 1)*2];
            ip3[1] = vkIC[(i + 1)*2+1];
            ip3[2] = input[i];

            // solium-disable-next-line security/no-inline-assembly
            assembly {
                success := staticcall(sub(gas(), 2000), 7, ip3, 0x80, add(ip4, 0x40), 0x60)
                // Use "invalid" to make gas estimation work
                switch success
                case 0 {
                    invalid()
                }
            }

            // solium-disable-next-line security/no-inline-assembly
            assembly {
                success := staticcall(sub(gas(), 2000), 6, ip4, 0xc0, add(ip4, 0), 0x60)
                // Use "invalid" to make gas estimation work
                switch success
                case 0 {
                    invalid()
                }
            }
        }

        // Compute the linear combination vk_x
        Pairing.G1Point memory vk_x;

        ip4[2] = vkIC[0];
        ip4[3] = vkIC[1];
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            success := staticcall(sub(gas(), 2000), 6, ip4, 0xc0, vk_x, 0x60)
            // Use "invalid" to make gas estimation work
            switch success
            case 0 {
            invalid()
            }
        }
        
        bool result = Pairing.pairing(
            proofA, proofB,
            vk.alfa1, vk.beta2,
            vk_x, vk.gamma2,
            proofC, vk.delta2
        );

        return result;
    }
}
