	.file	"12_run_matrix_scan.c"
	.text
	.globl	main                            # -- Begin function main
	.type	main,@function
main:                                   # @main
# %bb.0:
	addi	x2, x2, -16
	lx.matrix	x10, x0
	addi	x11, x2, 12
	sw	x10, 0(x11)
	addi	x10, x0, 5
	lx.chord	x10, x10
	addi	x11, x2, 8
	sw	x10, 0(x11)
	addi	x11, x2, 4
	addi	x10, x0, 0
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
	lw	x10, 0(x11)
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
	addi	x10, x0, 2
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
	addi	x10, x2, 12
	lw	x10, 0(x10)
	lx.report	x10
	addi	x10, x0, 0
	addi	x2, x2, 16
	jalr	x0, 0(x1)
.Lfunc_end0:
	.size	main, .Lfunc_end0-main
                                        # -- End function
	.ident	"clang version 23.0.0git (https://github.com/Axel84727/llvm-project-lx32.git 1124aa5a463f0d88df752564ca79023d0f690e60)"
	.section	".note.GNU-stack","",@progbits
