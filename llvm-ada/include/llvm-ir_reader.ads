pragma Ada_2005;
pragma Style_Checks (Off);

pragma Warnings (Off); with Interfaces.C; use Interfaces.C; pragma Warnings (On);
with LLVM.Types;
with System;

package LLVM.IR_Reader is

   function Parse_IR_In_Context
     (Context_Ref : LLVM.Types.Context_T;
      Mem_Buf : LLVM.Types.Memory_Buffer_T;
      Out_M : System.Address;
      Out_Message : System.Address) return LLVM.Types.Bool_T;  -- /chelles.b/users/charlet/git/gnat-llvm/llvm-ada/llvm-5.0.0.src/include/llvm-c/IRReader.h:32
   pragma Import (C, Parse_IR_In_Context, "LLVMParseIRInContext");

end LLVM.IR_Reader;

