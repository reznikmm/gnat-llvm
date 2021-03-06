pragma Style_Checks (Off);
pragma Warnings (Off, "*is already use-visible*");
pragma Warnings (Off, "*redundant with clause in body*");

with Interfaces.C;         use Interfaces.C;
pragma Unreferenced (Interfaces.C);
with Interfaces.C.Strings; use Interfaces.C.Strings;pragma Unreferenced (Interfaces.C.Strings);

package body LLVM.Target is

   function Create_Target_Data
     (String_Rep : String)
      return Target_Data_T
   is
      String_Rep_Array  : aliased char_array := To_C (String_Rep);
      String_Rep_String : constant chars_ptr := To_Chars_Ptr (String_Rep_Array'Unchecked_Access);
   begin
      return Create_Target_Data_C (String_Rep_String);
   end Create_Target_Data;

   function Copy_String_Rep_Of_Target_Data
     (TD : Target_Data_T)
      return String
   is
   begin
      return Value (Copy_String_Rep_Of_Target_Data_C (TD));
   end Copy_String_Rep_Of_Target_Data;

end LLVM.Target;
