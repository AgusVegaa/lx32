; ModuleID = '/Users/axel/Pulsar/tools/lx32_backend/tests/baremetal/programs/11_run_custom_intrinsics.c'
source_filename = "/Users/axel/Pulsar/tools/lx32_backend/tests/baremetal/programs/11_run_custom_intrinsics.c"
target datalayout = "e-m:e-p:32:32-p270:32:32-p271:32:32-p272:64:64-i128:128-f64:32:64-f80:32-n8:16:32-S128"
target triple = "i386-unknown-unknown-elf"

; Function Attrs: noinline nounwind optnone
define dso_local void @test_pulsar_custom_isa() #0 {
  %1 = alloca ptr, align 4
  %2 = alloca i32, align 4
  %3 = alloca i32, align 4
  %4 = alloca i32, align 4
  %5 = alloca i32, align 4
  %6 = alloca i32, align 4
  %7 = alloca i32, align 4
  %8 = alloca ptr, align 4
  %9 = alloca i32, align 4
  %10 = alloca i32, align 4
  store i32 3, ptr %6, align 4
  %11 = load i32, ptr %6, align 4
  %12 = call i32 @llvm.lx32.sensor(i32 %11)
  store volatile i32 %12, ptr %7, align 4
  store i32 0, ptr %5, align 4
  %13 = load i32, ptr %5, align 4
  %14 = call ptr @llvm.lx32.matrix(i32 %13)
  store ptr %14, ptr %8, align 4
  store i32 42, ptr %4, align 4
  %15 = load i32, ptr %4, align 4
  %16 = call i32 @llvm.lx32.delta(i32 %15)
  store volatile i32 %16, ptr %9, align 4
  store i32 42, ptr %3, align 4
  %17 = load i32, ptr %3, align 4
  %18 = call i32 @llvm.lx32.chord(i32 %17)
  store volatile i32 %18, ptr %10, align 4
  store i32 10, ptr %2, align 4
  %19 = load i32, ptr %2, align 4
  call void @llvm.lx32.wait(i32 %19)
  %20 = load ptr, ptr %8, align 4
  store ptr %20, ptr %1, align 4
  %21 = load ptr, ptr %1, align 4
  call void @llvm.lx32.report(ptr %21)
  %22 = load volatile i32, ptr %7, align 4
  %23 = load volatile i32, ptr %9, align 4
  %24 = load volatile i32, ptr %10, align 4
  ret void
}

; Function Attrs: noinline nounwind optnone
define dso_local void @test_large_wait() #0 {
  %1 = alloca i32, align 4
  %2 = alloca i32, align 4
  store i32 5000, ptr %1, align 4
  %3 = load i32, ptr %1, align 4
  call void @llvm.lx32.wait(i32 %3)
  store i32 4096, ptr %2, align 4
  %4 = load i32, ptr %2, align 4
  call void @llvm.lx32.wait(i32 %4)
  ret void
}

; Function Attrs: noinline nounwind optnone
define dso_local i32 @main() #0 {
  call void @test_pulsar_custom_isa() #3
  ret i32 0
}

; Function Attrs: nounwind memory(none)
declare i32 @llvm.lx32.sensor(i32) #1

; Function Attrs: nounwind memory(none)
declare ptr @llvm.lx32.matrix(i32) #1

; Function Attrs: nounwind memory(none)
declare i32 @llvm.lx32.delta(i32) #1

; Function Attrs: nounwind memory(none)
declare i32 @llvm.lx32.chord(i32) #1

; Function Attrs: nounwind
declare void @llvm.lx32.wait(i32) #2

; Function Attrs: nounwind
declare void @llvm.lx32.report(ptr) #2

attributes #0 = { noinline nounwind optnone "frame-pointer"="all" "min-legal-vector-width"="0" "no-builtins" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="generic" "target-features"="" "tune-cpu"="generic" }
attributes #1 = { nounwind memory(none) }
attributes #2 = { nounwind }
attributes #3 = { nobuiltin "no-builtins" }

!llvm.module.flags = !{!0, !1}
!llvm.ident = !{!2}

!0 = !{i32 1, !"NumRegisterParameters", i32 0}
!1 = !{i32 7, !"frame-pointer", i32 2}
!2 = !{!"clang version 23.0.0git (https://github.com/Axel84727/llvm-project-lx32.git 1124aa5a463f0d88df752564ca79023d0f690e60)"}
