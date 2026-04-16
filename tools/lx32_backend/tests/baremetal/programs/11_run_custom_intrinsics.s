	.file	"11_run_custom_intrinsics.c"
	.text
	.globl	test_pulsar_custom_isa          # -- Begin function test_pulsar_custom_isa
	.type	test_pulsar_custom_isa,@function
test_pulsar_custom_isa:                 # @test_pulsar_custom_isa
# %bb.0:
	addi	x2, x2, -40
	addi	x11, x2, 16
	addi	x12, x0, 3
	sw	x12, 0(x11)
	lw	x11, 0(x11)
	lx.sensor	x11, x11
	addi	x13, x2, 12
	sw	x11, 0(x13)
	addi	x11, x2, 20
	addi	x12, x0, 0
	sw	x12, 0(x11)
	lw	x11, 0(x11)
	lx.matrix	x11, x11
	addi	x14, x2, 8
	sw	x11, 0(x14)
	addi	x11, x2, 24
	addi	x15, x0, 42
	sw	x15, 0(x11)
	lw	x11, 0(x11)
	lx.delta	x11, x11
	addi	x12, x2, 4
	sw	x11, 0(x12)
	addi	x11, x2, 28
	sw	x15, 0(x11)
	lw	x11, 0(x11)
	lx.chord	x15, x11
	addi	x11, x2, 0
	sw	x15, 0(x11)
	addi	x15, x2, 32
	addi	x16, x0, 10
	sw	x16, 0(x15)
	lw	x15, 0(x15)
	lx.wait	x15
	lw	x15, 0(x14)
	addi	x14, x2, 36
	sw	x15, 0(x14)
	lw	x14, 0(x14)
	lx.report	x14
	lw	x13, 0(x13)
	lw	x12, 0(x12)
	lw	x11, 0(x11)
	addi	x2, x2, 40
	jalr	x0, 0(x1)
.Lfunc_end0:
	.size	test_pulsar_custom_isa, .Lfunc_end0-test_pulsar_custom_isa
                                        # -- End function
	.globl	test_large_wait                 # -- Begin function test_large_wait
	.type	test_large_wait,@function
test_large_wait:                        # @test_large_wait
# %bb.0:
	addi	x2, x2, -8
	lui	x11, 1
	addi	x13, x11, 904
	addi	x12, x2, 4
	sw	x13, 0(x12)
	lw	x12, 0(x12)
	lx.wait	x12
	addi	x12, x11, 0
	addi	x11, x2, 0
	sw	x12, 0(x11)
	lw	x11, 0(x11)
	lx.wait	x11
	addi	x2, x2, 8
	jalr	x0, 0(x1)
.Lfunc_end1:
	.size	test_large_wait, .Lfunc_end1-test_large_wait
                                        # -- End function
	.globl	main                            # -- Begin function main
	.type	main,@function
main:                                   # @main
# %bb.0:
	addi	x2, x2, -4
	sw	x1, 0(x2)
	jal	x1, <MCOperand Expr:test_pulsar_custom_isa>
	addi	x10, x0, 0
	lw	x1, 0(x2)
	addi	x2, x2, 4
	jalr	x0, 0(x1)
.Lfunc_end2:
	.size	main, .Lfunc_end2-main
                                        # -- End function
	.ident	"clang version 23.0.0git (https://github.com/Axel84727/llvm-project-lx32.git 1124aa5a463f0d88df752564ca79023d0f690e60)"
	.section	".note.GNU-stack","",@progbits
