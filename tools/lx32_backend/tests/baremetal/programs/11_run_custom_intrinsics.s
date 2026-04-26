	.file	"11_run_custom_intrinsics.c"
	.text
	.globl	test_pulsar_custom_isa          # -- Begin function test_pulsar_custom_isa
	.type	test_pulsar_custom_isa,@function
test_pulsar_custom_isa:                 # @test_pulsar_custom_isa
# %bb.0:
	addi	x2, x2, -40
	addi	x11, x0, 3
	sw	x11, 16(x2)
	lw	x11, 16(x2)
	lx.sensor	x11, x11
	sw	x11, 12(x2)
	addi	x11, x0, 0
	sw	x11, 20(x2)
	lw	x11, 20(x2)
	lx.matrix	x11, x11
	sw	x11, 8(x2)
	addi	x11, x0, 42
	sw	x11, 24(x2)
	lw	x12, 24(x2)
	lx.delta	x12, x12
	sw	x12, 4(x2)
	sw	x11, 28(x2)
	lw	x11, 28(x2)
	lx.chord	x11, x11
	sw	x11, 0(x2)
	addi	x11, x0, 10
	sw	x11, 32(x2)
	lw	x11, 32(x2)
	lx.wait	x11
	lw	x11, 8(x2)
	sw	x11, 36(x2)
	lw	x11, 36(x2)
	lx.report	x11
	lw	x11, 12(x2)
	lw	x11, 4(x2)
	lw	x11, 0(x2)
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
	addi	x12, x11, 904
	sw	x12, 4(x2)
	lw	x12, 4(x2)
	lx.wait	x12
	sw	x11, 0(x2)
	lw	x11, 0(x2)
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
