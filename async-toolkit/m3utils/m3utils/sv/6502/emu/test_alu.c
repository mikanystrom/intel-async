/*
 * test_alu.c -- Exhaustive verification of BDD-generated ALU eval functions
 *
 * Compares alu_bdd_eval.h against a reference C implementation of the
 * 6502 ALU for all input combinations (op 0..14, a/operand 0..255, carry 0..1).
 */

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

#include "alu_bdd_eval.h"

/* Reference ALU -- matches ALU.sv exactly */
static void ref_alu(uint8_t op, uint8_t a_in, uint8_t operand, uint8_t carry_in,
                    uint8_t *result, uint8_t *carry_out,
                    uint8_t *zero_out, uint8_t *sign_out,
                    uint8_t *overflow_out)
{
    uint16_t sum;
    *result = 0;
    *carry_out = 0;
    *overflow_out = 0;

    switch (op) {
    case 0: /* ADC */
        sum = (uint16_t)a_in + (uint16_t)operand + (carry_in & 1);
        *result = sum & 0xFF;
        *carry_out = (sum >> 8) & 1;
        *overflow_out = ((a_in ^ *result) & (operand ^ *result) & 0x80) ? 1 : 0;
        break;
    case 1: /* SBC */
        sum = (uint16_t)a_in + (uint16_t)(uint8_t)(~operand) + (carry_in & 1);
        *result = sum & 0xFF;
        *carry_out = (sum >> 8) & 1;
        *overflow_out = ((a_in ^ *result) & ((~operand) ^ *result) & 0x80) ? 1 : 0;
        break;
    case 2: /* AND */
        *result = a_in & operand;
        break;
    case 3: /* ORA */
        *result = a_in | operand;
        break;
    case 4: /* EOR */
        *result = a_in ^ operand;
        break;
    case 5: /* ASL */
        *carry_out = (operand >> 7) & 1;
        *result = operand << 1;
        break;
    case 6: /* LSR */
        *carry_out = operand & 1;
        *result = operand >> 1;
        break;
    case 7: /* ROL */
        *carry_out = (operand >> 7) & 1;
        *result = (operand << 1) | (carry_in & 1);
        break;
    case 8: /* ROR */
        *carry_out = operand & 1;
        *result = (operand >> 1) | ((carry_in & 1) << 7);
        break;
    case 9: /* INC */
        *result = operand + 1;
        break;
    case 10: /* DEC */
        *result = operand - 1;
        break;
    case 11: /* CMP */
        sum = (uint16_t)a_in + (uint16_t)(uint8_t)(~operand) + 1;
        *result = sum & 0xFF;
        *carry_out = (sum >> 8) & 1;
        break;
    case 12: /* BIT */
        *result = a_in & operand;
        *overflow_out = (operand >> 6) & 1;
        break;
    case 13: /* PASS_A */
        *result = a_in;
        break;
    case 14: /* PASS */
        *result = operand;
        break;
    default:
        *result = 0;
        break;
    }

    *zero_out = (*result == 0) ? 1 : 0;
    *sign_out = (*result >> 7) & 1;
}

int main(void) {
    long tests = 0, failures = 0;

    for (int op = 0; op <= 14; op++) {
        long op_failures = 0;
        for (int a = 0; a < 256; a++) {
            for (int b = 0; b < 256; b++) {
                for (int c = 0; c <= 1; c++) {
                    uint8_t r_ref, co_ref, zo_ref, so_ref, ov_ref;
                    ref_alu(op, a, b, c, &r_ref, &co_ref, &zo_ref, &so_ref, &ov_ref);

                    uint8_t r_bdd  = eval_result(op, a, b, c);
                    uint8_t co_bdd = eval_carry_out(op, a, b, c);
                    uint8_t zo_bdd = eval_zero_out(op, a, b, c);
                    uint8_t so_bdd = eval_sign_out(op, a, b, c);
                    uint8_t ov_bdd = eval_overflow_out(op, a, b, c);

                    int fail = 0;
                    if (r_bdd != r_ref) fail = 1;
                    if ((co_bdd & 1) != co_ref) fail = 1;
                    if ((zo_bdd & 1) != zo_ref) fail = 1;
                    if ((so_bdd & 1) != so_ref) fail = 1;
                    if ((ov_bdd & 1) != ov_ref) fail = 1;

                    if (fail && op_failures < 3) {
                        printf("MISMATCH op=%d a=0x%02X b=0x%02X c=%d: "
                               "ref(r=%02X co=%d zo=%d so=%d ov=%d) "
                               "bdd(r=%02X co=%d zo=%d so=%d ov=%d)\n",
                               op, a, b, c,
                               r_ref, co_ref, zo_ref, so_ref, ov_ref,
                               r_bdd, co_bdd & 1, zo_bdd & 1, so_bdd & 1, ov_bdd & 1);
                    }
                    if (fail) { failures++; op_failures++; }
                    tests++;
                }
            }
        }
        printf("  op %2d: %s", op, op_failures ? "FAIL" : "PASS");
        if (op_failures) printf(" (%ld mismatches)", op_failures);
        printf("\n");
    }

    printf("\n%ld tests, %ld failures\n", tests, failures);
    return failures ? 1 : 0;
}
