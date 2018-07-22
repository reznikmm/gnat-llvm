------------------------------------------------------------------------------
--                             G N A T - L L V M                            --
--                                                                          --
--                     Copyright (C) 2013-2018, AdaCore                     --
--                                                                          --
-- This is free software;  you can redistribute it  and/or modify it  under --
-- terms of the  GNU General Public License as published  by the Free Soft- --
-- ware  Foundation;  either version 3,  or (at your option) any later ver- --
-- sion.  This software is distributed in the hope  that it will be useful, --
-- but WITHOUT ANY WARRANTY;  without even the implied warranty of MERCHAN- --
-- TABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public --
-- License for  more details.  You should have  received  a copy of the GNU --
-- General  Public  License  distributed  with  this  software;   see  file --
-- COPYING3.  If not, go to http://www.gnu.org/licenses for a complete copy --
-- of the license.                                                          --
------------------------------------------------------------------------------

with Sinfo; use Sinfo;
with Uintp; use Uintp;

with LLVM.Core;   use LLVM.Core;

with GNATLLVM.Environment;  use GNATLLVM.Environment;
with GNATLLVM.GLValue;      use GNATLLVM.GLValue;
with GNATLLVM.Utils;        use GNATLLVM.Utils;

package GNATLLVM.Types is

   Max_Load_Size : constant := 128;
   --  LLVM supports loading and storing of arbitrarily-large values, but
   --  code generation and optimization is very slow if the value's size
   --  is too large.  We pick an arbitary constant here to cut it off.
   --  ??? Perhaps we should make this a command-line operand.

   function Create_Access_Type (TE : Entity_Id) return Type_T
     with Pre  => Is_Type (TE),
          Post => Present (Create_Access_Type'Result);
   --  Function that creates the access type for a corresponding type. Since
   --  access types are not just pointers, this is the abstraction bridge
   --  between the two.

   function GNAT_To_LLVM_Type
     (TE : Entity_Id; Definition : Boolean) return Type_T
     with Pre  => Is_Type (TE), Post => Present (GNAT_To_LLVM_Type'Result);

   function Create_Type (TE : Entity_Id) return Type_T is
      (GNAT_To_LLVM_Type (TE, False))
     with Pre => Present (TE), Post => Present (Create_Type'Result);

   function Create_TBAA (TE : Entity_Id) return Metadata_T
     with Pre => Is_Type (TE);

   procedure Bounds_From_Type (TE : Entity_Id; Low, High : out GL_Value)
     with Pre  => Ekind (TE) in Discrete_Kind,
          Post => Present (Low) and then Present (High);

   procedure Push_LValue_List;
   procedure Pop_LValue_List;
   --  Push and pop the active range of the LValue pair list

   procedure Clear_LValue_List;
   --  Remove all entries previously added to the LValue list

   procedure Add_To_LValue_List (V : GL_Value)
     with Pre => Present (V);
   --  Add V to the list that's searched by Get_Matching_Value

   function Add_To_LValue_List (V : GL_Value) return GL_Value
     with Pre => Present (V), Post => Add_To_LValue_List'Result = V;
   --  Likewise, but return V

   function Get_Matching_Value (TE : Entity_Id) return GL_Value
     with Pre  => Is_Type (TE),
          Post => Present (Get_Matching_Value'Result);
   --  Find a value that's being computed by the current Emit_LValue
   --  recursion that has the same base type as T.

   function Int_Ty (Num_Bits : Nat) return Type_T is
     (Int_Type (unsigned (Num_Bits)))
     with Post => Get_Type_Kind (Int_Ty'Result) = Integer_Type_Kind;

   function Int_Ty (Num_Bits : Uint) return Type_T is
     (Int_Type (unsigned (UI_To_Int (Num_Bits))))
     with Post => Get_Type_Kind (Int_Ty'Result) = Integer_Type_Kind;

   function Fn_Ty
     (Param_Ty : Type_Array;
      Ret_Ty   : Type_T;
      Varargs  : Boolean := False) return Type_T is
     (Function_Type
        (Ret_Ty, Param_Ty'Address, Param_Ty'Length, Varargs))
     with Pre  => Present (Ret_Ty),
          Post => Get_Type_Kind (Fn_Ty'Result) = Function_Type_Kind;

   function Build_Struct_Type
     (Types : Type_Array; Packed : Boolean := False) return Type_T
     with Post => Present (Build_Struct_Type'Result);
   --  Build an LLVM struct type containing the specified types

   function Get_Fullest_View
     (TE : Entity_Id; Include_PAT : Boolean := True) return Entity_Id
     with Pre => Is_Type_Or_Void (TE),
          Post => Is_Type_Or_Void (Get_Fullest_View'Result);
   --  Get the fullest possible view of E, looking through private,
   --  limited, packed array and other implementation types.  If Include_PAT
   --  is True, don't look inside packed array types.

   function Ultimate_Base_Type (TE : Entity_Id) return Entity_Id
     with Pre => Is_Type (TE), Post => Is_Type (Ultimate_Base_Type'Result);
   --  Go up TE's Etype chain until it points to itself, which will
   --  go up both base and parent types.

   function Full_Etype (N : Node_Id) return Entity_Id is
     (if Ekind (Etype (N)) = E_Void then Etype (N)
      else Get_Fullest_View (Etype (N)))
     with Pre => Present (N), Post => Is_Type_Or_Void (Full_Etype'Result);

   function Full_Component_Type (TE : Entity_Id) return Entity_Id is
     (Get_Fullest_View (Component_Type (TE)))
     with Pre  => Is_Array_Type (TE),
          Post => Present (Full_Component_Type'Result);

   function Full_Original_Array_Type (TE : Entity_Id) return Entity_Id is
     (Get_Fullest_View (Original_Array_Type (TE), Include_PAT => False))
     with Pre  => Is_Packed_Array_Impl_Type (TE),
          Post => Is_Array_Type (Full_Original_Array_Type'Result);

   function Full_Designated_Type (TE : Entity_Id) return Entity_Id is
     (Get_Fullest_View (Designated_Type (TE)))
     with Pre  => Is_Access_Type (TE),
          Post => Present (Full_Designated_Type'Result);

   function Full_Scope (E : Entity_Id) return Entity_Id is
     (Get_Fullest_View (Scope (E)))
     with Pre => Present (E), Post => Present (Full_Scope'Result);

   function Is_Unconstrained_Array (TE : Entity_Id) return Boolean is
     (Is_Array_Type (TE) and then not Is_Constrained (TE))
     with Pre => Is_Type_Or_Void (TE);

   function Is_Access_Unconstrained (TE : Entity_Id) return Boolean is
     (Is_Access_Type (TE)
        and then Is_Unconstrained_Array (Full_Designated_Type (TE)))
     with Pre => Is_Type (TE);

   function Is_Array_Or_Packed_Array_Type (TE : Entity_Id) return Boolean is
     (Is_Array_Type (TE) or else Is_Packed_Array_Impl_Type (TE))
     with Pre => Is_Type (TE);

   function Type_Needs_Bounds (TE : Entity_Id) return Boolean is
     ((Is_Constr_Subt_For_UN_Aliased (TE) and then Is_Array_Type (TE))
      or else (Is_Packed_Array_Impl_Type (TE)
                 and then Type_Needs_Bounds (Original_Array_Type (TE))))
     with Pre => Is_Type (TE);
   --  True is TE is a type that needs bounds stored with data

   function Convert
     (V              : GL_Value;
      TE             : Entity_Id;
      Float_Truncate : Boolean := False) return GL_Value
     with Pre  => Is_Elementary_Type (TE) and then Is_Elementary_Type (V),
          Post => Is_Elementary_Type (Convert'Result);
   --  Convert Expr to the type TE, with both the types of Expr and TE
   --  being elementary.

   function Convert
     (V, T : GL_Value; Float_Truncate : Boolean := False) return GL_Value is
     (Convert (V, Full_Etype (T), Float_Truncate))
     with Pre  => Is_Elementary_Type (V) and then Is_Elementary_Type (T),
          Post => Is_Elementary_Type (Convert'Result);
   --  Variant of above where the type is that of another value (T)

   function Convert_Ref (V : GL_Value; TE : Entity_Id) return GL_Value
     with Pre  => Present (V) and then Is_Type (TE),
          Post => Is_Access_Type (Convert_Ref'Result);
   --  Convert Src, which should be an access, into an access to Desig_Type

   function Convert_To_Access (V : GL_Value; TE : Entity_Id) return GL_Value
     with Pre  => Present (V) and then Is_Type (TE),
          Post => Is_Access_Type (Convert_To_Access'Result);
   --  Convert Src, which should be an access, into an access type TE

   function Convert_Ref
     (V : GL_Value; T : GL_Value) return GL_Value is
     (Convert_Ref (V, Full_Etype (T)))
     with Pre  => Present (V) and then Present (T),
          Post => Is_Access_Type (Convert_Ref'Result);
   --  Likewise, but get type from V

   function Convert_To_Access
     (V : GL_Value; T : GL_Value) return GL_Value is
     (Convert_To_Access (V, Full_Etype (T)))
     with Pre  => Present (V) and then Present (T),
          Post => Is_Access_Type (Convert_To_Access'Result);
   --  Likewise, but get type from V

   function Are_Arrays_With_Different_Index_Types
     (T1, T2 : Entity_Id) return Boolean
     with Pre => Is_Unconstrained_Array (T1) and then Is_Array_Type (T2);
   --  Return True iff T1 and T2 are array types that have at least
   --  one index for whose LLVM types are different.  T1 must be unconstrained.

   function Emit_Conversion
     (N                   : Node_Id;
      TE                  : Entity_Id;
      From_N              : Node_Id := Empty;
      Is_Unchecked        : Boolean := False;
      Need_Overflow_Check : Boolean := False;
      Float_Truncate      : Boolean := False) return GL_Value
     with Pre  => Is_Type (TE) and then Present (N)
                  and then TE = Get_Fullest_View (TE)
                  and then not (Is_Unchecked and Need_Overflow_Check),
          Post => Present (Emit_Conversion'Result);
   --  Emit code to convert Expr to Dest_Type, optionally in unchecked mode
   --  and optionally with an overflow check.  From_N is the conversion node,
   --  if there is a corresponding source node.

   function Emit_Convert_Value (N : Node_Id; TE : Entity_Id) return GL_Value is
     (Get (Emit_Conversion (N, TE), Object))
     with Pre  => Is_Type (TE) and then Present (N)
                  and then TE = Get_Fullest_View (TE),
          Post => Present (Emit_Convert_Value'Result);
   --  Emit code to convert Expr to Dest_Type and get it as a value

   function Convert_Pointer (V : GL_Value; TE : Entity_Id) return GL_Value
     with Pre  => Is_Access_Type (V),
          Post => Is_Access_Type (Convert_Pointer'Result);
   --  V is a reference to some object.  Convert it to a reference to TE
   --  with the same relationship.

   function Strip_Complex_Conversions (N : Node_Id) return Node_Id;
   --  Remove any conversion from N, if Present, if they are record or array
   --  conversions that increase the complexity of the size of the
   --  type because the caller will be doing any needed conversions.

   function Strip_Conversions (N : Node_Id) return Node_Id;
   --  Likewise, but remove all conversions

   function Bounds_To_Length
     (In_Low, In_High : GL_Value; TE : Entity_Id) return GL_Value
     with Pre  => Present (In_Low) and then Present (In_High)
                  and then Is_Type (TE)
                  and then Type_Of (In_Low) = Type_Of (In_High),
          Post => Full_Etype (Bounds_To_Length'Result) = TE;
   --  Low and High are bounds of a discrete type.  Compute the length of
   --  that type, taking into account the superflat case, and do that
   --  computation in TE.  We would like to have the above test be that the
   --  two types be identical, but that's too strict (for example, one
   --  may be Integer and the other Integer'Base), so just check the width.

   function Get_LLVM_Type_Size (T : Type_T) return ULL is
     (ABI_Size_Of_Type (Module_Data_Layout, T))
     with Pre => Present (T);
   --  Return the size of an LLVM type, in bytes

   function Get_LLVM_Type_Size (T : Type_T) return GL_Value is
     (Size_Const_Int (Get_LLVM_Type_Size (T)));
   --  Return the size of an LLVM type, in bytes, as an LLVM constant

   function Get_LLVM_Type_Size_In_Bits (T : Type_T) return ULL is
     (Size_Of_Type_In_Bits (Module_Data_Layout, T))
     with Pre => Present (T);
   --  Return the size of an LLVM type, in bits

   function Get_LLVM_Type_Size_In_Bits (V : GL_Value) return ULL is
     (Size_Of_Type_In_Bits (Module_Data_Layout, Type_Of (V.Value)))
     with Pre => Present (V);
   --  Return the size of an LLVM type, in bits

   function Get_LLVM_Type_Size_In_Bits (T : Type_T) return GL_Value is
     (Const_Int (Size_Type, Get_LLVM_Type_Size_In_Bits (T), False))
     with Pre  => Present (T),
          Post => Present (Get_LLVM_Type_Size_In_Bits'Result);
   --  Return the size of an LLVM type, in bits, as an LLVM constant

   function Get_LLVM_Type_Size_In_Bits (TE : Entity_Id) return GL_Value
     with Pre  => Present (TE),
          Post => Present (Get_LLVM_Type_Size_In_Bits'Result);
   --  Likewise, but convert from a GNAT type

   function Get_LLVM_Type_Size_In_Bits (V : GL_Value) return GL_Value is
     (Get_LLVM_Type_Size_In_Bits (V.Typ))
     with Pre  => Present (V),
          Post => Present (Get_LLVM_Type_Size_In_Bits'Result);
   --  Variant of above to get type from a GL_Value

   function Is_Loadable_Type (TE : Entity_Id) return Boolean is
     (not Is_Dynamic_Size (TE)
        and then Get_LLVM_Type_Size (Create_Type (TE)) < ULL (Max_Load_Size))
     with Pre => Is_Type (TE);
   --  Returns True if we should use a load/store instruction to copy values
   --  of this type.  We can't do this if it's of dynamic size, but LLVM
   --  doesn't do well with large load/store instructions, so we make an
   --  arbitrary cap here of 128 bytes and use memcpy if larger.

   function Allocate_For_Type
     (TE         : Entity_Id;
      Alloc_Type : Entity_Id;
      N          : Node_Id;
      V          : GL_Value := No_GL_Value;
      Name       : String := "") return GL_Value
     with Pre  => Is_Type (TE) and then Is_Type (Alloc_Type),
          Post => Is_Access_Type (Allocate_For_Type'Result);
   --  Allocate space on the stack for an object of type TE and return
   --  a pointer to the space.  Name is the name to use for the LLVM
   --  value.  If Value is Present, it's a value to be copyied to the
   --  temporary and can be used to size the allocated space.  N is a node
   --  used for a Sloc if we have to raise an exception.

   function Heap_Allocate_For_Type
     (TE         : Entity_Id;
      Alloc_Type : Entity_Id;
      V          : GL_Value  := No_GL_Value;
      Proc       : Entity_Id := Empty;
      Pool       : Entity_Id := Empty) return GL_Value
     with Pre  => Is_Type (TE) and then Is_Type (Alloc_Type)
                  and then (No (Proc) or else Present (Pool)),
          Post => Is_Access_Type (Heap_Allocate_For_Type'Result);
   --  Similarly, but allocate storage on the heap.  This will handle
   --  default allocation, secondary stack, and storage pools.

   procedure Heap_Deallocate (V : GL_Value; Proc : Entity_Id; Pool : Entity_Id)
     with Pre => Present (V)
                  and then (No (Proc) or else Present (Pool));
   --  Free memory allocated by Heap_Allocate_For_Type

   function To_Size_Type (V : GL_Value) return GL_Value is
     (Convert (V, Size_Type))
     with Pre  => Present (V),
          Post => Type_Of (To_Size_Type'Result) = LLVM_Size_Type;
   --  Convert V to Size_Type.  This is always Size_Type's width, but may
   --  actually be a different GNAT type.

   function Align_To (V, Cur_Align, Must_Align : GL_Value) return GL_Value
     with Pre => Present (V), Post => Present (Align_To'Result);
   --  V is a value aligned to Cur_Align.  Ensure that it's aligned to
   --  Align_To.

   function Get_Type_Alignment (T : Type_T) return unsigned is
     (ABI_Alignment_Of_Type (Module_Data_Layout, T))
     with Pre => Present (T);
   --  Return the size of an LLVM type, in bits

   function Get_Type_Alignment (TE : Entity_Id) return unsigned
     with Pre => Is_Type (TE);
   --  Return the size of a GNAT type, in bits

   function Get_Type_Size
     (TE       : Entity_Id;
      V        : GL_Value := No_GL_Value;
      Max_Size : Boolean  := False) return GL_Value
     with Pre => Is_Type (TE), Post => Present (Get_Type_Size'Result);
   --  Return the size of a type, in bytes, as a GL_Value.  If TE is
   --  an unconstrained array type, V must be the value of the array.

   function Compute_Size
     (Left_Type, Right_Type   : Entity_Id;
      Left_Value, Right_Value : GL_Value) return GL_Value
     with Pre  => Is_Type (Left_Type) and then Present (Right_Type)
                  and then Present (Right_Value),
          Post =>  Present (Compute_Size'Result);
   --  Used for comparison and assignment: compute the size to be used in
   --  the operation.  Right_Value must be specified.  Left_Value is
   --  optional and will be specified in the comparison case, but not the
   --  assignment case.  If Right_Value is a discriminated record, we
   --  assume here that the last call to Emit_LValue was to compute
   --  Right_Value so that we can use Get_Matching_Value to return the
   --  proper object.  In the comparison case, where Left_Value is
   --  specified, we can only be comparing arrays, so we won't need to
   --  use Get_Matching_Value.

   function Compute_Alignment
     (Left_Type, Right_Type : Entity_Id) return unsigned is
     (unsigned'Max (Get_Type_Alignment (Left_Type),
                    Get_Type_Alignment (Right_Type)))
     with Pre  => Is_Type (Left_Type) and then Is_Type (Right_Type);
   --  Likewise, but compute strictest alignment in bits

   function Get_Type_Size_Complexity
     (TE : Entity_Id; Max_Size : Boolean := False) return Nat
     with Pre  => Is_Type (TE);
   --  Return the complexity of computing the size of a type.  This roughly
   --  gives the number of "things" needed to access to compute the size.
   --  This returns zero iff the type is of a constant size.

   procedure Add_Type_Data_To_Instruction (Inst : Value_T; TE : Entity_Id);
   --  Add type data (e.g., volatility and TBAA info) to an Instruction

end GNATLLVM.Types;
