	.file	"10_matrix_scan.c"
	.text
	.globl	test_complex_scan               # -- Begin function test_complex_scan
	.type	test_complex_scan,@function
test_complex_scan:                      # @test_complex_scan
# %bb.0:
	addi	x2, x2, -36
	addi	x11, x2, 16
	addi	x10, x0, 0
	sw	x10, 0(x11)
	lw	x11, 0(x11)
	lx.matrix	x11, x11
	addi	x12, x2, 12
	sw	x11, 0(x12)
	addi	x11, x2, 20
	addi	x12, x0, 5
	sw	x12, 0(x11)
	lw	x11, 0(x11)
	lx.chord	x11, x11
	addi	x12, x2, 8
	sw	x11, 0(x12)
	addi	x11, x2, 4
	sw	x10, 0(x11)
	jal	x0, <MCOperand Expr:.LBB0_1>
.LBB0_1:                                # =>This Inner Loop Header: Depth=1
	addi	x10, x2, 4
	lw	x11, 0(x10)
	addi	x10, x0, 63
	blt	x10, x11, <MCOperand Expr:.LBB0_7>
	jal	x0, <MCOperand Expr:.LBB0_2>
.LBB0_2:                                #   in Loop: Header=BB0_1 Depth=1
	addi	x11, x2, 4
	lw	x12, 0(x11)
	addi	x10, x2, 24
	sw	x12, 0(x10)
	lw	x10, 0(x10)
	lx.delta	x10, x10
	addi	x12, x2, 0
	sw	x10, 0(x12)
	addi	x10, x2, 12
	lw	x10, 0(x10)
	lw	x11, 0(x11)
	slli	x11, x11, 1
	add	x10, x10, x11
	lhu	x11, 0(x10)
	addi	x10, x0, 2000
	blt	x10, x11, <MCOperand Expr:.LBB0_4>
	jal	x0, <MCOperand Expr:.LBB0_3>
.LBB0_3:                                #   in Loop: Header=BB0_1 Depth=1
	addi	x10, x2, 0
	lw	x10, 0(x10)
	addi	x11, x0, 101
	blt	x10, x11, <MCOperand Expr:.LBB0_5>
	jal	x0, <MCOperand Expr:.LBB0_4>
.LBB0_4:                                #   in Loop: Header=BB0_1 Depth=1
	addi	x10, x2, 28
	addi	x11, x0, 2
	sw	x11, 0(x10)
	lw	x10, 0(x10)
	lx.wait	x10
	jal	x0, <MCOperand Expr:.LBB0_5>
.LBB0_5:                                #   in Loop: Header=BB0_1 Depth=1
	jal	x0, <MCOperand Expr:.LBB0_6>
.LBB0_6:                                #   in Loop: Header=BB0_1 Depth=1
	addi	x11, x2, 4
	lw	x10, 0(x11)
	addi	x10, x10, 1
	sw	x10, 0(x11)
	jal	x0, <MCOperand Expr:.LBB0_1>
.LBB0_7:
	addi	x11, x2, 12
	lw	x12, 0(x11)
	addi	x11, x2, 32
	sw	x12, 0(x11)
	lw	x11, 0(x11)
	lx.report	x11
	addi	x2, x2, 36
	jalr	x0, 0(x1)
.Lfunc_end0:
	.size	test_complex_scan, .Lfunc_end0-test_complex_scan
                                        # -- End function
	.globl	main                            # -- Begin function main
	.type	main,@function
main:                                   # @main
# %bb.0:
	addi	x2, x2, -4
	sw	x1, 0(x2)
	jal	x1, <MCOperand Expr:test_complex_scan>
	addi	x10, x0, 0
	lw	x1, 0(x2)
	addi	x2, x2, 4
	jalr	x0, 0(x1)
.Lfunc_end1:
	.size	main, .Lfunc_end1-main
                                        # -- End function
	.ident	"clang version 23.0.0git (https://github.com/Axel84727/llvm-project-lx32.git 1124aa5a463f0d88df752564ca79023d0f690e60)"
	.section	".note.GNU-stack","",@progbits
