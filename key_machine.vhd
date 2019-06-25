----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    15:26:34 06/04/2019 
-- Design Name: 
-- Module Name:    key_machine - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity key_machine is
	port(
	   clk, reset: in  std_logic;
      ps2d, ps2c: in  std_logic;
      key: out std_logic_vector(7 downto 0);
		flag_ler: out std_logic
	);
end key_machine;

architecture Behavioral of key_machine is

component kb_code is
   generic(W_SIZE: integer:=2);  -- 2^W_SIZE words in FIFO
   port (
      clk, reset: in  std_logic;
      ps2d, ps2c: in  std_logic;
      rd_key_code: in std_logic;
      key_code: out std_logic_vector(7 downto 0);
      kb_buf_empty: out std_logic
   );
end component kb_code;

signal estado: std_logic;
signal flush: std_logic;
signal key_code: std_logic_vector (7 downto 0) := "00000000";
signal Key_buf: std_logic_vector (7 downto 0) := "00000000";
signal state: natural range 0 to 2 := 0;
signal clkcount:unsigned (5 downto 0) := "000000";
signal oneusclk: std_logic; 

begin

kbcode: kb_code port map(clk, reset, ps2d, ps2c, flush, key_code, estado);
key <= key_buf;

	--  This process counts to 50, and then resets.  It is used to divide the clock signal time.
	process (CLK, oneUSClk)
    		begin
			if (CLK = '1' and CLK'event) then
				clkCount <= clkCount + 1;
			end if;
		end process;
	--  This makes oneUSClock peak once every 1 microsecond

	oneUSClk <= clkCount(5);

process(oneUSClk,estado,state,reset)
begin
	if (reset = '1') then 
		state <= 0;
		flush <= '0'; 
		flag_ler <= '0';
		key_buf <= "00000000";
	elsif (oneUSClk'event and ONEUSClk='1') then
		case state is
			when 0 => if estado = '0' then
							state <=1;
							flush <= '1'; 
							flag_ler <= '0';
							key_buf <= key_code;
						else
							state <= 0;
							flush <='0';
							flag_ler <= '0';
							key_buf <= key_buf;
						 end if;
			when 1 => 
				flag_ler <= '1'; 
				state <= 2;
				flush <= '0';		
					key_buf <= key_buf;
			when 2 => flush <= '0'; 
						 flag_ler <= '0';
						 state <= 0;  
						 key_buf <= key_buf;
			end case;
		end if;
   end process;
end Behavioral;