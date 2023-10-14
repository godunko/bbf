------------------------------------------------------------------------------
--                                                                          --
--                           Bare Board Framework                           --
--                                                                          --
------------------------------------------------------------------------------
--
--  Copyright (C) 2019-2023, Vadim Godunko <vgodunko@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
--

pragma Restrictions (No_Elaboration_Code);

package body BBF.Drivers.MPU.MPU6500 is

   ----------------
   -- Initialize --
   ----------------

   not overriding procedure Initialize
     (Self    : in out MPU6500_Sensor;
      Delays  : not null access BBF.Delays.Delay_Controller'Class;
      Success : in out Boolean) is
   begin
      Self.Internal_Initialize (Delays, MPU6500_WHOAMI, Success);

      if not Success then
         --  Check may be removed after change convention about Success in I2C.

         return;
      end if;

      --  Initialize common data structures and defaults.

      Self.Internal_Initialize (Success);
   end Initialize;

end BBF.Drivers.MPU.MPU6500;
