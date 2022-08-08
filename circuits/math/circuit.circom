pragma circom 2.0.0;

include "../node_modules/circomlib/circuits/comparators.circom";
include "../node_modules/circomlib/circuits/switcher.circom";
include "../node_modules/circomlib/circuits/sign.circom";
include "../node_modules/circomlib/circuits/bitify.circom";

include "../crypto/encrypt.circom";
include "../crypto/ecdh.circom";
include "../range_proof/circuit.circom";

template Uint82Num(pack) {
    signal input in[pack];
    signal output out;
    var lc1=0;

    for (var i = 0; i<pack; i++) {
        lc1 += in[i] * 256**i;
    }

    lc1 ==> out;
}

template Num2Uint8(pack) {
    signal input in;
    signal output out[pack];
    var lc1 = 0;

    component rps[pack];

    var e2 = 1;
    for (var i = 0; i<pack; i++) {
        
        out[i] <-- (in >> i * 8) & 255;
        
        rps[i] = LessThan(9);
        rps[i].in[0] <== out[i];
        rps[i].in[1] <== 256;
        rps[i].out === 1;
        
        lc1 += out[i] * e2;
        e2 = e2 * 256;
    }

    lc1 === in;
}


template IsNegative(){
    signal input in;
    signal output out;
    component n2b = Num2Bits(254);
    component sign = Sign();
    in ==> n2b.in;
    for (var i = 0; i<254; i++) {
        n2b.out[i] ==> sign.in[i];
    }
    sign.sign ==> out;
}

// input: dividend and divisor field elements in [0, sqrt(p))
// output: remainder and quotient field elements in [0, p-1] and [0, sqrt(p)
// Haven't thought about negative divisor yet. Not needed.
// -8 % 5 = 2. [-8 -> 8. 8 % 5 -> 3. 5 - 3 -> 2.]
// (-8 - 2) // 5 = -2
// -8 + 2 * 5 = 2
// check: 2 - 2 * 5 = -8
template Modulo(divisor_bits) {
    signal input dividend; // -8
    signal input divisor; // 5
    signal output remainder; // 2
    signal output quotient; // -2

    component is_neg = IsNegative();
    is_neg.in <== dividend;

    signal output is_dividend_negative;
    is_dividend_negative <== is_neg.out;

    signal output dividend_adjustment;
    dividend_adjustment <== 1 + is_dividend_negative * -2; // 1 or -1

    signal output abs_dividend;
    abs_dividend <== dividend * dividend_adjustment; // 8

    signal output raw_remainder;
    raw_remainder <== abs_dividend % divisor;
    
    signal output neg_remainder;
    neg_remainder <== divisor - raw_remainder;

    if (is_dividend_negative == 1 && raw_remainder != 0) {
        remainder <-- neg_remainder;
    } else {
        remainder <-- raw_remainder;
    }

    quotient <-- (dividend - remainder) / divisor; // (-8 - 2) / 5 = -2.

    dividend === divisor * quotient + remainder; // -8 = 5 * -2 + 2.

    component rp = MultiRangeProof(3, 128, 147946756881789309620446562439722434560); // SQRT_P
    rp.in[0] <== divisor;
    rp.in[1] <== quotient;
    rp.in[2] <== dividend;

    // check that 0 <= remainder < divisor
    component remainderUpper = LessThan(divisor_bits);
    remainderUpper.in[0] <== remainder;
    remainderUpper.in[1] <== divisor;
    remainderUpper.out === 1;
}

template PositiveModulo(divisor_bits) {
    signal input dividend; // -8
    signal input divisor; // 5
    signal output remainder; // 2
    signal output quotient; // -2
 
    signal output abs_dividend;
    abs_dividend <== dividend; //* dividend_adjustment; // 8
 
    signal output raw_remainder;
    raw_remainder <-- abs_dividend % divisor;
 
    remainder <-- raw_remainder;
    
    quotient <-- (dividend - remainder) / divisor; // (-8 - 2) / 5 = -2.
 
    dividend === divisor * quotient + remainder; // -8 = 5 * -2 + 2.
 
    // check that 0 <= remainder < divisor
    component remainderUpper = LessThan(divisor_bits);
    remainderUpper.in[0] <== remainder;
    remainderUpper.in[1] <== divisor;
    remainderUpper.out === 1;
    
}