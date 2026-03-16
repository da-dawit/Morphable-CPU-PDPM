/* Vector Ops — Unrolled Array Computation
 * Element-wise add/xor on arrays, no branches
 * Target: P7 (zero branches, pure throughput)
 */
volatile int A[8];
volatile int B[8];
volatile int C[8];
void main(void) {
    A[0]=1; A[1]=2; A[2]=3; A[3]=4; A[4]=5; A[5]=6; A[6]=7; A[7]=8;
    B[0]=8; B[1]=7; B[2]=6; B[3]=5; B[4]=4; B[5]=3; B[6]=2; B[7]=1;
    C[0]=A[0]+B[0]; C[1]=A[1]+B[1]; C[2]=A[2]+B[2]; C[3]=A[3]+B[3];
    C[4]=A[4]+B[4]; C[5]=A[5]+B[5]; C[6]=A[6]+B[6]; C[7]=A[7]+B[7];
    A[0]=C[0]^B[0]; A[1]=C[1]^B[1]; A[2]=C[2]^B[2]; A[3]=C[3]^B[3];
    A[4]=C[4]^B[4]; A[5]=C[5]^B[5]; A[6]=C[6]^B[6]; A[7]=C[7]^B[7];
    B[0]=C[0]-A[0]; B[1]=C[1]-A[1]; B[2]=C[2]-A[2]; B[3]=C[3]-A[3];
    B[4]=C[4]-A[4]; B[5]=C[5]-A[5]; B[6]=C[6]-A[6]; B[7]=C[7]-A[7];
    int sum=0;
    sum+=C[0]+C[1]+C[2]+C[3]+C[4]+C[5]+C[6]+C[7];
    sum+=A[0]+A[1]+A[2]+A[3]+A[4]+A[5]+A[6]+A[7];
    sum+=B[0]+B[1]+B[2]+B[3]+B[4]+B[5]+B[6]+B[7];
    asm volatile("mv a0, %0" : : "r"(sum));
}
