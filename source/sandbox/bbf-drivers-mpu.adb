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

with Ada.Unchecked_Conversion;
with System.Address_To_Access_Conversions;
with System.Storage_Elements;

with BBF.Board;
with BBF.External_Interrupts;
with BBF.HPL.PMC;  --  XXX Need to be removed.

package body BBF.Drivers.MPU is

   type CONFIG_Resgisters is record
      SMPLRT_DIV     : Registers.SMPLRT_DIV_Register;
      CONFIG         : Registers.CONFIG_Register;
      GYRO_CONFIG    : Registers.GYRO_CONFIG_Register;
      ACCEL_CONFIG   : Registers.ACCEL_CONFIG_Register;
      ACCEL_CONFIG_2 : Registers.MPU6500_ACCEL_CONFIG_2_Register;
   end record
     with Pack, Object_Size => 40;

   type PWR_MGMT_Registers is record
      PWR_MGMT_1 : Registers.PWR_MGMT_1_Register;
      PWR_MGMT_2 : Registers.PWR_MGMT_2_Register;
   end record
     with Pack, Object_Size => 16;

   type INT_Registers is record
      INT_PIN_CFG : Registers.INT_PIN_CFG_Register;
      INT_ENABLE  : Registers.INT_ENABLE_Register;
   end record
     with Object_Size => 16;

   procedure On_Interrupt (Closure : System.Address);

   procedure On_FIFO_Count_Read (Closure : System.Address);

   procedure On_FIFO_Data_Read (Closure : System.Address);

   package Conversions is
     new System.Address_To_Access_Conversions
           (Object => Abstract_MPU_Sensor'Class);

   ---------------
   -- Configure --
   ---------------

   procedure Configure
     (Self                : in out Abstract_MPU_Sensor'Class;
      Delays              : not null access BBF.Delays.Delay_Controller'Class;
      Accelerometer_Range : Accelerometer_Range_Type;
      Gyroscope_Range     : Gyroscope_Range_Type;
      Temperature         : Boolean;
      Filter              : Boolean;
      Sample_Rate         : Sample_Rate_Type;
      Success             : in out Boolean)
   is
      use type Interfaces.Unsigned_8;

      SMPLRT_DIV : constant Interfaces.Unsigned_8 :=
        Interfaces.Unsigned_8
          ((if Filter then 1_000 else 8_000) / Sample_Rate - 1);
      --  MPU6500 has additional 8_000 and 32_000 modes, however, this value is
      --  used only when DLPF in 1 .. 6.

      CONFIG     : constant CONFIG_Resgisters :=
        (SMPLRT_DIV     =>
           (SMPLRT_DIV => SMPLRT_DIV),
           --  MPU6050: Gyro rate is 8k when CONFIG:DLPF_CFG = 0, and
           --  1k overwise. MPU6500: Depends from CONFIG:DLPF_CFG and
           --  GYRO_CFG:FCHOICE_B, looks compatible with allowed MPU6050
           --  values.
         CONFIG         =>
           (DLPF_CFG          =>
                (if not Filter then 0
                 elsif Sample_Rate >= 188 * 2 then 1
                 elsif Sample_Rate >=  98 * 2 then 2
                 elsif Sample_Rate >=  42 * 2 then 3
                 elsif Sample_Rate >=  20 * 2 then 4
                 elsif Sample_Rate >=  10 * 2 then 5
                                              else 6),
            --  MPU6500 support value 7 to bypass filter, not implemented.
            EXT_SYNC_SET      => Registers.Disabled,
            MPU6500_FIFO_MODE => False,
            others            => False),
         --  Enable DLPF_CFG, rate will be about 180 Hz.
         GYRO_CONFIG    =>
           (MPU6500_FCHOICE_B => 0,
            GYRO_FS_SEL       =>
              (case Gyroscope_Range is
                  when FSR_250DPS  => Registers.G_250,
                  when FSR_500DPS  => Registers.G_500,
                  when FSR_1000DPS => Registers.G_1000,
                  when FSR_2000DPS => Registers.G_2000,
                  when Disabled    => Registers.GYRO_FS_SEL_Type'First),
            others            => False),
         ACCEL_CONFIG   =>
           (ACCEL_FS_SEL =>
                (case Accelerometer_Range is
                    when FSR_2G   => Registers.A_2,
                    when FSR_4G   => Registers.A_4,
                    when FSR_8G   => Registers.A_8,
                    when FSR_16G  => Registers.A_16,
                    when Disabled => Registers.ACCEL_FS_SEL_Type'First),
            others       => False),
         ACCEL_CONFIG_2 =>
           (A_DLPF_CFG     =>
                (if not Filter then 0
                 elsif Sample_Rate >= 188 * 2 then 1
                 elsif Sample_Rate >=  98 * 2 then 2
                 elsif Sample_Rate >=  42 * 2 then 3
                 elsif Sample_Rate >=  20 * 2 then 4
                 elsif Sample_Rate >=  10 * 2 then 5
                                              else 6),
            ACCEL_CHOICE_B => False,
            FIFO_SIZE_1024 => True,
            --  MPU6500 shares 4kB of memory between the DMP and the FIFO.
            --  Since the first 3kB are needed by the DMP, we'll use the
            --  last 1kB for the FIFO.
            others         => False));
         --  This register is available on MPU6500/9250 only. Selected values
         --  run accelerometer at about 180 Hz, like gyro.
      CONFIG_B   : constant BBF.I2C.Unsigned_8_Array (1 .. 5)
        with Import, Convention => Ada, Address => CONFIG'Address;

      PWR_MGMT   : constant PWR_MGMT_Registers :=
        (PWR_MGMT_1 =>
           (CLKSEL   =>
                (if Gyroscope_Range /= Disabled
                   then Registers.PLL_X
                   else Registers.Internal),
                 --  On MPU6500 Auto (PLL_X) can be used always
            TEMP_DIS => not Temperature,
            SLEEP    =>
              Accelerometer_Range = Disabled
                and Gyroscope_Range = Disabled
                and not Temperature,
            others => <>),
         PWR_MGMT_2 =>
           (STBY_ZG => Gyroscope_Range = Disabled,
            STBY_YG => Gyroscope_Range = Disabled,
            STBY_XG => Gyroscope_Range = Disabled,
            STBY_ZA => Accelerometer_Range = Disabled,
            STBY_YA => Accelerometer_Range = Disabled,
            STBY_XA => Accelerometer_Range = Disabled,
            others  => <>));
      PWR_MGMT_B : constant BBF.I2C.Unsigned_8_Array (1 .. 2)
        with Import, Convention => Ada, Address => PWR_MGMT'Address;

   begin
      if not Success then
         return;
      end if;

      if not Self.Initialized then
         Success := False;

         return;
      end if;

      --  Configuration of SMPLRT_DIV is set to lower gyro rate on MPU6050 to
      --  rate of the accelerometer.
      --
      --  DLPF is enabled and DLPF_CFG/FCHOICE_B set to have gyro rate 184 Hz.
      --  It is possible to lower gyro rate and have it close to accelerometer
      --  rate.
      --
      --  On MPU6500/9250 accelerometer configured to 188 Hz rate. It is
      --  separate rergister on these sensors, on MPU6050/9150 when DLPF
      --  is configured it applies to both gyro and accelerometer.
      --
      --  MPU6500/9250 has more modes, but they are not compatible with
      --  MPU6050/9150 and not useful for my purposes.

      Self.Bus.Write_Synchronous
        (Self.Device,
         SMPLRT_DIV_Address,
         CONFIG_B (1 .. (if Self.Is_6500_9250 then 5 else 4)),
         Success);
      Self.Bus.Write_Synchronous
        (Self.Device, PWR_MGMT_1_Address, PWR_MGMT_B, Success);

      Delays.Delay_Milliseconds (50);

      Self.Accelerometer_Enabled := Accelerometer_Range /= Disabled;
      Self.Gyroscope_Enabled     := Gyroscope_Range /= Disabled;
      Self.Temperature_Enabled   := Temperature;
   end Configure;

   ------------
   -- Enable --
   ------------

   procedure Enable
     (Self   : in out Abstract_MPU_Sensor'Class;
      Delays : not null access BBF.Delays.Delay_Controller'Class)
   is
      Success : Boolean := True;

   begin
      --  Disable everything

      declare
         INT_ENABLE   : constant Registers.INT_ENABLE_Register :=
           (others => False);
         INT_ENABLE_B : constant Interfaces.Unsigned_8
           with Import, Address => INT_ENABLE'Address;
         FIFO_EN      : constant Registers.FIFO_EN_Register :=
           (others => False);
         FIFO_EN_B    : constant Interfaces.Unsigned_8
           with Import, Address => FIFO_EN'Address;
         USER_CTRL    : constant Registers.USER_CTRL_Register :=
           (others => False);
         USER_CTRL_B  : constant Interfaces.Unsigned_8
           with Import, Address => USER_CTRL'Address;

      begin
         Self.Bus.Write_Synchronous
           (Self.Device, INT_ENABLE_Address, INT_ENABLE_B, Success);
         Self.Bus.Write_Synchronous
           (Self.Device, FIFO_EN_Address, FIFO_EN_B, Success);
         Self.Bus.Write_Synchronous
           (Self.Device, USER_CTRL_Address, USER_CTRL_B, Success);
      end;

      --  Reset FIFO

      declare
         USER_CTRL   : constant Registers.USER_CTRL_Register :=
           (FIFO_RESET => True,
            others     => False);
         USER_CTRL_B : constant Interfaces.Unsigned_8
           with Import, Address => USER_CTRL'Address;

      begin
         Self.Bus.Write_Synchronous
           (Self.Device, USER_CTRL_Address, USER_CTRL_B, Success);
      end;

      --  Enable FIFO, interrupts and configure sensors to report

      declare
         INT         : constant INT_Registers :=
           (INT_PIN_CFG  =>
              (ACTL             => True,
               LATCH_INT_EN     => True,
               INT_ANYRD_2CLEAR => True,
               others           => <>),
            INT_ENABLE   =>
              (RAW_RDY_EN => True,
               others     => False));
         INT_B       : constant BBF.I2C.Unsigned_8_Array (1 .. 2)
           with Import, Address => INT'Address;
         USER_CTRL   : constant Registers.USER_CTRL_Register :=
           (FIFO_EN => True,
            others  => False);
         USER_CTRL_B : constant Interfaces.Unsigned_8
           with Import, Address => USER_CTRL'Address;
         FIFO_EN     : constant Registers.FIFO_EN_Register :=
           (ACCEL_FIFO_EN => Self.Accelerometer_Enabled,
            XG_FIFO_EN    => Self.Gyroscope_Enabled,
            YG_FIFO_EN    => Self.Gyroscope_Enabled,
            ZG_FIFO_EN    => Self.Gyroscope_Enabled,
            TEMP_FIFO_EN  => Self.Temperature_Enabled,
            others        => False);
         FIFO_EN_B   : constant Interfaces.Unsigned_8
           with Import, Address => FIFO_EN'Address;

      begin
         Self.Bus.Write_Synchronous
           (Self.Device, USER_CTRL_Address, USER_CTRL_B, Success);

         Delays.Delay_Milliseconds (50);

         Self.Bus.Write_Synchronous
           (Self.Device, INT_PIN_CFG_Address, INT_B, Success);
         Self.Bus.Write_Synchronous
           (Self.Device, FIFO_EN_Address, FIFO_EN_B, Success);
      end;

      if not Success then
         return;
      end if;

      --  Configure pin to generate interrupts

      BBF.HPL.PMC.Enable_Peripheral_Clock (BBF.HPL.Parallel_IO_Controller_C);
      --  XXX Must be moved out!

      BBF.Board.Pin_50.Configure (BBF.External_Interrupts.Falling_Edge);
      BBF.Board.Pin_50.Set_Handler (On_Interrupt'Access, Self'Address);
      BBF.Board.Pin_50.Enable_Interrupt;
   end Enable;

   -------------------------
   -- Internal_Initialize --
   -------------------------

   procedure Internal_Initialize
     (Self    : in out Abstract_MPU_Sensor'Class;
      Delays  : not null access BBF.Delays.Delay_Controller'Class;
      WHOAMI  : Interfaces.Unsigned_8;
      Success : in out Boolean)
   is
      use type Interfaces.Unsigned_8;

      Buffer : Interfaces.Unsigned_8;

   begin
      Self.Initialized := False;

      if not Success then
         return;
      end if;

      --  Do controller's probe.

      Success := Self.Bus.Probe (Self.Device);

      if not Success then
         return;
      end if;

      --  Check controller's WHOAMI code

      Self.Bus.Read_Synchronous
        (Self.Device, MPU.WHO_AM_I_Address, Buffer, Success);

      if not Success then
         return;

      elsif Buffer /= WHOAMI then
         Success := False;

         return;
      end if;

      --  Device reset

      declare
         PWR_MGMT_1   : constant Registers.PWR_MGMT_1_Register :=
           (DEVICE_RESET => True,
            CLKSEL       => Registers.Internal,
            others       => <>);
         PWR_MGMT_1_B : Interfaces.Unsigned_8
           with Address => PWR_MGMT_1'Address;

      begin
         Self.Bus.Write_Synchronous
           (Self.Device, PWR_MGMT_1_Address, PWR_MGMT_1_B, Success);

         if not Success then
            return;
         end if;
      end;

      Delays.Delay_Milliseconds (100);

      --  Signal path reset

      declare
         SIGNAL_PATH_RESET   : Registers.SIGNAL_PATH_RESET_Register :=
           (TEMP_Reset  => True,
            ACCEL_Reset => True,
            GYRO_Reset  => True,
            others      => <>);
         SIGNAL_PATH_RESET_B : Interfaces.Unsigned_8
           with Address => SIGNAL_PATH_RESET'Address;

      begin
         Self.Bus.Write_Synchronous
           (Self.Device,
            SIGNAL_PATH_RESET_Address,
            SIGNAL_PATH_RESET_B,
            Success);

         if not Success then
            return;
         end if;
      end;

      Delays.Delay_Milliseconds (100);

      --  Wakeup

      declare
         PWR_MGMT_1   : Registers.PWR_MGMT_1_Register :=
           (SLEEP  => False,
            CLKSEL => Registers.Internal,
            others => <>);
         PWR_MGMT_1_B : Interfaces.Unsigned_8
           with Address => PWR_MGMT_1'Address;

      begin
         Self.Bus.Write_Synchronous
           (Self.Device, PWR_MGMT_1_Address, PWR_MGMT_1_B, Success);
      end;

      Self.Initialized := True;
   end Internal_Initialize;

   ------------------------
   -- On_FIFO_Count_Read --
   ------------------------

   procedure On_FIFO_Count_Read (Closure : System.Address) is
      use type Interfaces.Unsigned_16;

      Self    : constant Conversions.Object_Pointer :=
        Conversions.To_Pointer (Closure);
      Size    : constant Interfaces.Unsigned_16 :=
        (if Self.Accelerometer_Enabled then 6 else 0)
          + (if Self.Gyroscope_Enabled then 6 else 0)
          + (if Self.Temperature_Enabled then 2 else 0);
      Amount  : constant Interfaces.Unsigned_16 :=
        Interfaces.Unsigned_16 (Self.Buffer (1)) * 256
          + Interfaces.Unsigned_16 (Self.Buffer (2));
      Success : Boolean := True;

   begin
      if Amount < Size then
         --  Not enough data available.

         return;
      end if;

      Self.Bus.Read_Asynchronous
        (Device     => Self.Device,
         Register   => FIFO_R_W_Address,
         Data       => Self.Buffer (1)'Address,
         Length     => Size,
         On_Success => On_FIFO_Data_Read'Access,
         On_Error   => null,
         Closure    => Closure,
         Success    => Success);
   end On_FIFO_Count_Read;

   -----------------------
   -- On_FIFO_Data_Read --
   -----------------------

   procedure On_FIFO_Data_Read (Closure : System.Address) is

      use type Interfaces.Unsigned_8;
      use type System.Storage_Elements.Storage_Offset;

      Self   : constant Conversions.Object_Pointer :=
        Conversions.To_Pointer (Closure);
      Offset : System.Storage_Elements.Storage_Offset := 0;

      Data   : Raw_Data renames Self.Raw_Data (not Self.User_Bank);

   begin
      if Self.Accelerometer_Enabled then
         declare
            Aux : constant ACCEL_OUT_Register
              with Import, Address => Self.Buffer'Address + Offset;

         begin
            Data.ACCEL := Aux;
            Offset     := Offset + 6;
         end;

      else
         Data.ACCEL := (others => <>);
      end if;

      if Self.Temperature_Enabled then
         declare
            Aux : constant TEMP_OUT_Register
              with Import, Address => Self.Buffer'Address + Offset;

         begin
            Data.TEMP := Aux;
            Offset    := Offset + 2;
         end;

      else
         Data.TEMP := (others => <>);
      end if;

      if Self.Gyroscope_Enabled then
         declare
            Aux : constant GYRO_OUT_Register
              with Import, Address => Self.Buffer'Address + Offset;

         begin
            Data.GYRO := Aux;
            Offset    := Offset + 6;
         end;

      else
         Data.GYRO := (others => <>);
      end if;

      Data.Timestamp := Self.Clocks.Clock;
      Self.User_Bank := not @;
   end On_FIFO_Data_Read;

   ------------------------
   -- On_INT_STATUS_Read --
   ------------------------

   procedure On_INT_STATUS_Read (Closure : System.Address) is
      Self       : constant Conversions.Object_Pointer :=
        Conversions.To_Pointer (Closure);
      INT_STATUS : constant Registers.IN_STATUS_Register
        with Import, Address => Self.Buffer (1)'Address;

      Success    : Boolean := True;

   begin
      if INT_STATUS.FIFO_OFLOW_EN then
         --  FIFO overflow, operations should be shutdown and FIFO is
         --  restarted.
         --  XXX Not implemented.

         raise Program_Error with "MPU6xxx FIFO OVERFLOW";
      end if;

      if not INT_STATUS.DATA_RDY_INT then
         --  Data is not ready

         return;
      end if;

      --  Initiate load of amount of data available in FIFO.

      Self.Bus.Read_Asynchronous
        (Device     => Self.Device,
         Register   => FIFO_COUNT_H_Address,
         Data       => Self.Buffer (1)'Address,
         Length     => 2,
         On_Success => On_FIFO_Count_Read'Access,
         On_Error   => null,
         Closure    => Closure,
         Success    => Success);
   end On_INT_STATUS_Read;

   ------------------
   -- On_Interrupt --
   ------------------

   procedure On_Interrupt (Closure : System.Address) is
      Self    : constant Conversions.Object_Pointer :=
        Conversions.To_Pointer (Closure);
      Success : Boolean := True;

   begin
      --  Initiate read of INT_STATUS register.
      --
      --  Unfortunately, read of FIFO_COUNT is not enough: sometimes FIFO_COUNT
      --  has size of block, but when block is downloaded it contains all zero
      --  bytes. It is happend when INT_STATUS.DATA_RDY_INT is not set. Thus,
      --  first read INT_STATUS and continue operation only then DATA_RDY_INT
      --  is set.

      Self.Bus.Read_Asynchronous
        (Device     => Self.Device,
         Register   => INT_STATUS_Address,
         Data       => Self.Buffer (1)'Address,
         Length     => 1,
         On_Success => On_INT_STATUS_Read'Access,
         On_Error   => null,
         Closure    => Closure,
         Success    => Success);
   end On_Interrupt;

   -------------------------
   -- To_Angular_Velosity --
   -------------------------

   function To_Angular_Velosity
     (Self : Abstract_MPU_Sensor'Class;
      H    : Interfaces.Integer_8;
      L    : Interfaces.Unsigned_8) return Angular_Velosity
   is
      use type Interfaces.Integer_32;

      function Convert is
        new Ada.Unchecked_Conversion
              (Interfaces.Integer_32, Angular_Velosity);

      B : constant Register_16 :=
        (Is_Integer => False,
         H          => H,
         L          => L);
      V : constant Interfaces.Integer_32 :=
        Interfaces.Integer_32 (B.V) * 1_000 * 8;

   begin
      return Convert (V);
   end To_Angular_Velosity;

   -----------------------------------
   -- To_Gravitational_Acceleration --
   -----------------------------------

   function To_Gravitational_Acceleration
     (Self : Abstract_MPU_Sensor'Class;
      H    : Interfaces.Integer_8;
      L    : Interfaces.Unsigned_8) return Gravitational_Acceleration
   is
      use type Interfaces.Integer_32;

      function Convert is
        new Ada.Unchecked_Conversion
              (Interfaces.Integer_32, Gravitational_Acceleration);

      B : constant Register_16 :=
        (Is_Integer => False,
         H          => H,
         L          => L);
      V : constant Interfaces.Integer_32 := Interfaces.Integer_32 (B.V) * 8;

   begin
      return Convert (V);
   end To_Gravitational_Acceleration;

end BBF.Drivers.MPU;
