------------------------------------------------------------------------------
--                             G N A T - L L V M                            --
--                                                                          --
--                     Copyright (C) 2013-2019, AdaCore                     --
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

with Table;

with LLVM.Core; use LLVM.Core;

with GNATLLVM.Environment; use GNATLLVM.Environment;

package body GNATLLVM.GLType is

   --  A GL_Type can be of various different kinds.  We list them here.

   type GT_Kind is
     (Primitive,
      --  This is the actual type to perform computations in

      Padded,
      --  This is a record whose first field is the primitive type and
      --  the second is padding to make the record the proper length.  This
      --  can only be done if the primitive type is a native LLVM type.

      Byte_Array,
      --  This is an array of bytes (i8) whose length is the desired size of
      --  the GL_Type.  This should only be used when the primitive type is
      --  not a native LLVM type.

      Aligning);
     --  This is the same LLVM type as for the primitive type, but recorded
     --  to indicate that we need to align it differently.  This should only
     --  be used when the primitive type is not a native LLVM type.

   --  Define the fields in the table for GL_Type's

   type GL_Type_Info_Base is record
      GNAT_Type : Entity_Id;
      --  GNAT type

      LLVM_Type : Type_T;
      --  LLVM type used for this alternative

      Next      : GL_Type;
      --  If Present, link to next alternative

      Size      : GL_Value;
      --  If Present, size of this alternative

      Alignment : GL_Value;
      --  If Present, alignment of this alternative

      Bias      : GL_Value;
      --  If Present, the amount of bias for integral types

      Max_Size  : Boolean;
      --  If True, this corresponds to the maxumum size of an unconstrained
      --  variant record with default discriminant values;

      Kind      : GT_Kind;
      --  Says what type of alternative type this is

      Default   : Boolean;
      --  Marks the default GL_Type

   end record;
   --  We want to put a Predicate on this, but can't, so we need to make
   --  a subtype for that purpose.

   function GL_Type_Info_Is_Valid (GTI : GL_Type_Info_Base) return Boolean;
   --  Return whether GT is a valid GL_Type or not

   subtype GL_Type_Info is GL_Type_Info_Base
     with Predicate => GL_Type_Info_Is_Valid (GL_Type_Info);
   --  Subtype used by everybody except validation function

   function GL_Type_Info_Is_Valid_Int (GTI : GL_Type_Info_Base) return Boolean;
   --  Internal version of GL_Value_Is_Valid

   package GL_Type_Table is new Table.Table
     (Table_Component_Type => GL_Type_Info,
      Table_Index_Type     => GL_Type'Base,
      Table_Low_Bound      => GL_Type_Low_Bound,
      Table_Initial        => 2000,
      Table_Increment      => 200,
      Table_Name           => "GL_Type_Table");

   function  Next (GT : GL_Type) return GL_Type
     with Pre => Present (GT);
   procedure Next (GT : in out GL_Type)
     with Pre => Present (GT);

   ---------------------------
   -- GL_Type_Info_Is_Valid --
   ---------------------------

   function GL_Type_Info_Is_Valid (GTI : GL_Type_Info_Base) return Boolean is
      Valid : constant Boolean := GL_Type_Info_Is_Valid_Int (GTI);
   begin
      --  This function exists so a conditional breakpoint can be set at
      --  the following line to see the invalid value.  Otherwise, there
      --  seems no other reasonable way to get to see it.

      return Valid;
   end GL_Type_Info_Is_Valid;

   -------------------------------
   -- GL_Type_Info_Is_Valid_Int --
   -------------------------------

   function GL_Type_Info_Is_Valid_Int
     (GTI : GL_Type_Info_Base) return Boolean is
   begin
      if No (GTI.GNAT_Type) or else No (GTI.LLVM_Type)
        or else (Present (GTI.Size) and then not Is_A_Const_Int (GTI.Size))
        or else (Present (GTI.Bias) and then not Is_A_Const_Int (GTI.Bias))
        or else (Present (GTI.Alignment)
                   and then not Is_A_Const_Int (GTI.Alignment))
      then
         return False;
      end if;

      case GTI.Kind is
         when Primitive =>
            return True;
         when Padded =>
            return not Is_Nonnative_Type (GTI.GNAT_Type)
              and then Get_Type_Kind (GTI.LLVM_Type) = Struct_Type_Kind;
         when Byte_Array =>
            return Is_Nonnative_Type (GTI.GNAT_Type)
              and then Get_Type_Kind (GTI.LLVM_Type) = Array_Type_Kind;
         when Aligning =>
            return Is_Nonnative_Type (GTI.GNAT_Type);
      end case;

   end GL_Type_Info_Is_Valid_Int;

   ----------
   -- Next --
   ----------

   function  Next (GT : GL_Type) return GL_Type is
     (GL_Type_Table.Table (GT).Next);

   ----------
   -- Next --
   ----------

   procedure Next (GT : in out GL_Type) is
   begin
      GT := GL_Type_Table.Table (GT).Next;
   end Next;

   --------------------
   -- Create_GL_Type --
   --------------------

   function Create_GL_Type
     (TE       : Entity_Id;
      Size     : Uint    := No_Uint;
      Align    : Uint    := No_Uint;
      Max_Size : Boolean := False;
      Biased   : Boolean := False) return GL_Type
   is
      pragma Unreferenced (Biased);
      Size_V  : constant GL_Value :=
        (if   Size = No_Uint then No_GL_Value
         else Size_Const_Int ((Size + (Uint_Bits_Per_Unit - 1)) /
                                Uint_Bits_Per_Unit));
      Align_V : constant GL_Value :=
        (if Align = No_Uint then No_GL_Value else Size_Const_Int (Align));
      GT      : GL_Type           := Get_GL_Type (TE);
      Last    : GL_Type           := GT;

   begin
      --  See if we already have made a matching GL_Type

      while Present (GT) loop
         declare
            GTI : constant GL_Type_Info := GL_Type_Table.Table (GT);
         begin
            --  For now, they're equal only if everything matches

            if Size_V = GTI.Size and then Align_V = GTI.Alignment
              and then Max_Size = GTI.Max_Size
            then
               return GT;
            end if;
         end;

         Last := GT;
         Next (GT);
      end loop;

      --  Otherwise, we have to create an entry.  ??? Ignore everything but
      --  TE when making the LLVM type for now.

      GL_Type_Table.Append ((GNAT_Type => TE,
                             LLVM_Type => Create_Primitive_Type (TE),
                             Next      => No_GL_Type,
                             Size      => Size_V,
                             Alignment => Align_V,
                             Bias      => No_GL_Value,
                             Max_Size  => Max_Size,
                             Kind      => Primitive,
                             Default   => True));
      if No (Last) then
         Set_GL_Type (TE, GL_Type_Table.Last);
      else
         GL_Type_Table.Table (Last).Next := GL_Type_Table.Last;
      end if;

      return GL_Type_Table.Last;
   end Create_GL_Type;

   --------------------
   -- Update_GL_Type --
   --------------------

   procedure Update_GL_Type (GT : GL_Type) is
      GTI : GL_Type_Info renames GL_Type_Table.Table (GT);

   begin
      GTI.LLVM_Type := Create_Primitive_Type (GTI.GNAT_Type);
   end Update_GL_Type;

   -----------------------
   -- Primitive_GL_Type --
   -----------------------

   function Primitive_GL_Type (TE : Entity_Id) return GL_Type is
      GT : GL_Type := Get_GL_Type (TE);

   begin
      --  If there's no GL_Type yet, make one

      if No (GT) then
         return Create_GL_Type (TE);
      end if;

      while Present (GT) loop
         exit when GL_Type_Table.Table (GT).Kind = Primitive;
         Next (GT);
      end loop;

      return GT;
   end Primitive_GL_Type;

   ---------------------
   -- Default_GL_Type --
   ---------------------

   function Default_GL_Type (TE : Entity_Id) return GL_Type is
      GT : GL_Type := Get_GL_Type (TE);

   begin
      --  If there's no GL_Type yet, make one

      if No (GT) then
         return Create_GL_Type (TE);
      end if;

      while Present (GT) loop
         exit when GL_Type_Table.Table (GT).Default;
         Next (GT);
      end loop;

      return GT;
   end Default_GL_Type;

   ------------------
   -- Mark_Default --
   ------------------

   procedure Mark_Default (GT : GL_Type) is
      All_GT : GL_Type := Get_GL_Type (Full_Etype (GT));

   begin
      --  Mark all GT's as default or not, depending on whether it's ours

      while Present (All_GT) loop
         GL_Type_Table.Table (All_GT).Default := All_GT = GT;
         Next (All_GT);
      end loop;
   end Mark_Default;

   ----------------
   -- Full_Etype --
   ----------------

   function Full_Etype (GT : GL_Type) return Entity_Id is
     (GL_Type_Table.Table (GT).GNAT_Type);

   -------------
   -- Type_Of --
   -------------

   function Type_Of (GT : GL_Type) return Type_T is
     (GL_Type_Table.Table (GT).LLVM_Type);

   -------------------
   -- Get_Type_Size --
   -------------------

   function Get_Type_Size (GT : GL_Type) return GL_Value is
      GTI  : constant GL_Type_Info := GL_Type_Table.Table (GT);
      Size : GL_Value              := GTI.Size;

   begin
      --  If we know the size of this alternative, use it.  Otherwise, get
      --  the size of the GNAT type, taking into account a request for
      --  the maximum size.

      if No (Size) then
         Size := Get_Type_Size (GTI.GNAT_Type, Max_Size => GTI.Max_Size);
      end if;

      return Size;

   end Get_Type_Size;

   ------------------------
   -- Get_Type_Alignment --
   ------------------------

   function Get_Type_Alignment (GT : GL_Type) return GL_Value is
      GTI : constant GL_Type_Info := GL_Type_Table.Table (GT);

   begin
      --  If we know the alignment of this alternative, use it.  Otherwise,
      --  get the alignment of the GNAT type.

      if Present (GTI.Alignment) then
         return GTI.Alignment;
      else
         return Get_Type_Alignment (GTI.GNAT_Type);
      end if;
   end Get_Type_Alignment;

   --------------------
   --  Is_Dummy_Type --
   --------------------

   function Is_Dummy_Type (GT : GL_Type) return Boolean is
     (Is_Dummy_Type (Full_Etype (GT)));

   -----------------------
   -- Is_Nonnative_Type --
   -----------------------

   function Is_Nonnative_Type (GT : GL_Type) return Boolean is
      GTI  : constant GL_Type_Info := GL_Type_Table.Table (GT);

   begin
      --  If we've built an LLVM type to do padding, then that's a native
      --  type.  Otherwise, we have to look at whether the underlying type
      --  has a native representation or not.

      return GTI.Kind not in Padded | Byte_Array
        and then Is_Nonnative_Type (GTI.GNAT_Type);
   end Is_Nonnative_Type;

begin
   --  Make a dummy entry in the table, so the "No" entry is never used.

   GL_Type_Table.Increment_Last;
end GNATLLVM.GLType;
