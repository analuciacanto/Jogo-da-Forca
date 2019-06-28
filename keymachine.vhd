 
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity keymachine is
  port (
    clk, reset  : in STD_LOGIC; -- FPGA Clock
    ps2d, ps2c  : in STD_LOGIC;
    leds        : out STD_LOGIC_VECTOR (7 downto 0);
    keyPressed  : out STD_LOGIC);
end keymachine;


architecture Behavioral of keymachine is

  component kb_code port (
    clk, reset      : in STD_LOGIC; -- FPGA Clock
    ps2d, ps2c      : in STD_LOGIC;
    rd_key_code     : in STD_LOGIC; -- Free the buffer
    key_code        : out STD_LOGIC_VECTOR (7 downto 0);
    kb_buf_empty    : out STD_LOGIC -- Key written on buffer?
    );
  end component kb_code;
  
  component key2ascii port (
    key_code: in std_logic_vector(7 downto 0);
	 ascii_code : out std_logic_vector(7 downto 0));
  end component key2ascii;

  type states is (
    initState,
    midState,
    endState);

  SIGNAL actualState    : states := initState;
  signal nextState      : states;
  signal freeBuf     : std_logic := '0';
  signal keyRead        : STD_LOGIC_VECTOR (7 downto 0) := "00000000";
  signal keyBuf      : STD_LOGIC_VECTOR (7 downto 0);
  signal emptyBuf    : STD_LOGIC;

  signal redClk : std_logic := '0'; -- reducted clock


begin
  kbc: kb_code port map (clk, reset, ps2d, ps2c, freeBuf, keyBuf, emptyBuf);
  k2a: key2ascii port map (keyRead, keyBuf);
  leds <= keyRead;

  process (clk)
    variable count : UNSIGNED (5 downto 0) := "000000";

  BEGIN
    if (clk = '1' and clk'event) then
      if (count >= 9) then
        count := "000000";
        redClk <= not redClk;
      else
        count := count + 1;
      end if;
    end if;
  end process;

  process(redClk, actualState, emptyBuf)
  begin
    if (redClk = '1' and redClk'event) then
      if actualState = initState then
        if emptyBuf = '0' then
          actualState <= midState;
        end if;
      end if;
      if actualState = midState then
        actualState <= endState;
      end if;
      if actualState = endState then
        actualState <= initState;
      end if;
    end if;
  end process;

  process(redClk)
  begin
    if actualState = initState then
      freeBuf <= '0';
    end if;
    if actualState = midState then
      keyRead <= keyBuf;
    end if;
    if actualState = endState then
      freeBuf <= '1';
    end if;
  end process;
end Behavioral;