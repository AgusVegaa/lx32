; RUN: llc -march=lx32 -mcpu=generic -mtriple=lx32-unknown-elf -filetype=asm -o - %s

define i32 @branch_unsigned(i32 %a, i32 %b) {
entry:
  %cmp = icmp ult i32 %a, %b
  br i1 %cmp, label %lt, label %ge

lt:
  ret i32 1

ge:
  ret i32 0
}

