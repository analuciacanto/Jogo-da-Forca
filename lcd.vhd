library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_ARITH.all;
use IEEE.STD_LOGIC_UNSIGNED.all;

entity lcd is
  port (LCD_DB : out std_logic_vector(7 downto 0);  --DB( 7 through 0)
        RS     : out std_logic;                     --WE
        RW     : out std_logic;                     --ADR(0)
        CLK    : in  std_logic;                     --GCLK2
        --ADR1:out std_logic;                --ADR(1)
        --ADR2:out std_logic;                --ADR(2)
        --CS:out std_logic;              --CSC
        OE     : out std_logic;                     --OE
        rst    : in  std_logic;                    --BTN
  --rdone: out std_logic);         --WriteDone output to work with DI05 test
        leds : out std_logic_vector (7 downto 0);
        ps2d, ps2c : std_logic);
end lcd;

architecture Behavioral of lcd is

------------------------------------------------------------------
--  Component Declarations
------------------------------------------------------------------
  component kb_code port (
    clk, reset   : in  std_logic;       --clk da fpga
    ps2d, ps2c   : in  std_logic;
    rd_key_code  : in  std_logic;       -- libera o buffer
    key_code     : out std_logic_vector(7 downto 0);  --tecla no buffer
    kb_buf_empty : out std_logic        -- tecla foi escrita no buffer
    );
  end component kb_code;
------------------------------------------------------------------

------------------------------------------------------------------
--  Local Type Declarations
-----------------------------------------------------------------
--  Symbolic names for all possible states of the state machines.

  --LCD control state machine
  type mstate is (
    stFunctionSet,                      --Initialization states
    stDisplayCtrlSet,
    stDisplayClear,
    stPowerOn_Delay,                    --Delay states
    stFunctionSet_Delay,
    stDisplayCtrlSet_Delay,
    stDisplayClear_Delay,
    stInitDne,        --Display charachters and perform standard operations
    stActWr,
    stCharDelay                         --Write delay for operations
   --stWait                    --Idle state
    );

  --Write control state machine
  type wstate is (
    stRW,                               --set up RS and RW
    stEnable,                           --set up E
    stIdle                              --Write data on DB(0)-DB(7)
    );

  type gameState is (
    idleState,
    hitState,
    missState,
    loseState
    );

  type readState is (
    initRead,
    midRead,
    endRead
    );

  signal clkCount  : std_logic_vector(5 downto 0);
  signal activateW : std_logic                      := '0';  --Activate Write sequence
  signal count     : std_logic_vector (16 downto 0) := "00000000000000000";  --15 bit count variable for timing delays
  signal delayOK   : std_logic                      := '0';  --High when count has reached the right delay time
  signal OneUSClk  : std_logic;  --Signal is treated as a 1 MHz clock    
  signal stCur     : mstate                         := stPowerOn_Delay;  --LCD control state machine

  signal stNext    : mstate;
  signal stCurW    : wstate    := stIdle;  --Write control state machine
  signal stNextW   : wstate;
  signal writeDone : std_logic := '0';     --Command set finish

  --signal := idleState;
  signal nextState : gameState;
  signal actualState : readState := initRead;

  signal freeBuf    : std_logic                     := '0';
  signal keyRead    : std_logic_vector (7 downto 0) := "00000000";
  signal keyBuf     : std_logic_vector (7 downto 0);
  signal emptyBuf   : std_logic;
  signal errorCount : unsigned (3 downto 0)         := "0000";
  signal keyPressed : std_logic                     := '0';
  signal teclaLida  : std_logic                     := '0';


 type showVector is array (integer range 0 to 5) of std_logic_vector(9 downto 0);
  signal show : showVector := (
    0 => "10"&X"2E",
    1 => "10"&X"2E",
    2 => "10"&X"2E",
    3 => "10"&X"2E",
    4 => "10"&X"2E",
    5 => "10"&X"2E"	 
    );
	 	 
	type LCD_CMDS_T is array(integer range 0 to 12) of std_logic_vector(9 downto 0);
	SIGNAL LCD_CMDS : LCD_CMDS_T := 
						( 0 => "00"&X"3C",			--Function Set
					    1 => "00"&X"0C",			--Display ON, Cursor OFF, Blink OFF
					    2 => "00"&X"01",			--Clear Display
					    3 => "00"&X"02", 			--return home
					    4 => "10"&X"74", 			--T  --P --G
					    5 => "10"&X"1C",  			--A  --E	--A
					    6 => "10"&X"6F",  			--O  --R	--N	
					    7 => "10"&X"6C", 			--K  --D --H
					    8 => "10"&X"65", 			--E  --E --O
					    9 => "10"&X"20",  			--Y  --U --U
					    10 => "10"&X"20", 		   --BLANK SPACE --!					   
					    11 => "10"&X"46",  	   -- Número de erros	
						 12 => "00"&X"02" 			--return home
						 
						 
); 

  signal lcd_cmd_ptr : integer range 0 to LCD_CMDS'high + 1 := 0;
begin
  leds(0) <= keyRead(0);
  leds(1) <= keyRead(1);
  leds(2) <= keyRead(2);
  leds(3) <= keyRead(3);
  leds(4) <= keyRead(4);
  leds(5) <= keyRead(5);
  leds(6) <= keyRead(6);
  leds(7) <= keyRead(7);
  
  LCD_CMDS(0) <= "00"&X"3C";            --Function Set
  LCD_CMDS(1) <= "00"&X"0C";            --Display ON, Cursor OFF, Blink OFF
  LCD_CMDS(2) <= "00"&X"01";            --Clear Display
  LCD_CMDS(3) <= "00"&X"02";            --return home

  LCD_CMDS(4) <= show(0);
  LCD_CMDS(5) <= show(1);
  LCD_CMDS(6) <= show(2);
  LCD_CMDS(7) <= show(3);
  LCD_CMDS(8) <= show(4);
  LCD_CMDS(9) <= show(5); 
  
  LCD_CMDS(10) <= "1000100000";

  LCD_CMDS(11)  <= "10"&"0011"&(std_logic_vector(errorCount));
 
  kbc : kb_code port map (clk, rst, ps2d, ps2c, freeBuf, keyBuf, emptyBuf);

  --  This process counts to 50, and then resets.  It is used to divide the clock signal time.
  process (CLK, oneUSClk)
  begin
    if (CLK = '1' and CLK'event) then
      clkCount <= clkCount + 1;
    end if;
  end process;
  --  This makes oneUSClock peak once every 1 microsecond

  oneUSClk <= clkCount(5);
  --  This process incriments the count variable unless delayOK = 1.
  process (oneUSClk, delayOK)
  begin
    if (oneUSClk = '1' and oneUSClk'event) then
      if delayOK = '1' then
        count <= "00000000000000000";
      else
        count <= count + 1;
      end if;
    end if;
  end process;

  --This goes high when all commands have been run
  writeDone <= '1' when (lcd_cmd_ptr = LCD_CMDS'high)
               else '0';
  --rdone <= '1' when stCur = stWait else '0';
  --Increments the pointer so the statemachine goes through the commands
  process (lcd_cmd_ptr, oneUSClk)
  begin
    if (oneUSClk = '1' and oneUSClk'event) then
      if ((stNext = stInitDne or stNext = stDisplayCtrlSet or stNext = stDisplayClear) and writeDone = '0') then
        lcd_cmd_ptr <= lcd_cmd_ptr + 1;
      elsif stCur = stPowerOn_Delay or stNext = stPowerOn_Delay then
        lcd_cmd_ptr <= 0;
      elsif keyPressed = '1' then
        lcd_cmd_ptr <= 3;
      else
        lcd_cmd_ptr <= lcd_cmd_ptr;
      end if;
    end if;
  end process;

  --  Determines when count has gotten to the right number, depending on the state.

  delayOK <= '1' when ((stCur = stPowerOn_Delay and count = "00100111001010010") or  --20050  
                       (stCur = stFunctionSet_Delay and count = "00000000000110010") or  --50
                       (stCur = stDisplayCtrlSet_Delay and count = "00000000000110010") or  --50
                       (stCur = stDisplayClear_Delay and count = "00000011001000000") or  --1600
                       (stCur = stCharDelay and count = "11111111111111111"))  --Max Delay for character writes and shifts
             --(stCur = stCharDelay and count = "00000000000100101"))        --37  This is proper delay between writes to ram.
             else '0';

  -- This process runs the LCD status state machine
  process (oneUSClk, rst)
  begin
    if oneUSClk = '1' and oneUSClk'event then
      if rst = '1' then
        stCur <= stPowerOn_Delay;
      else
        stCur <= stNext;
      end if;
    end if;
  end process;


  --  This process generates the sequence of outputs needed to initialize and write to the LCD screen
  process (stCur, delayOK, writeDone, lcd_cmd_ptr, LCD_CMDS)
  begin

    case stCur is

      --  Delays the state machine for 20ms which is needed for proper startup.
      when stPowerOn_Delay =>
        if delayOK = '1' then
          stNext <= stFunctionSet;
        else
          stNext <= stPowerOn_Delay;
        end if;
        RS        <= LCD_CMDS(lcd_cmd_ptr)(9);
        RW        <= LCD_CMDS(lcd_cmd_ptr)(8);
        LCD_DB    <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
        activateW <= '0';

      -- This issuse the function set to the LCD as follows 
      -- 8 bit data length, 2 lines, font is 5x8.
      when stFunctionSet =>
        RS        <= LCD_CMDS(lcd_cmd_ptr)(9);
        RW        <= LCD_CMDS(lcd_cmd_ptr)(8);
        LCD_DB    <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
        activateW <= '1';
        stNext    <= stFunctionSet_Delay;

      --Gives the proper delay of 37us between the function set and
      --the display control set.
      when stFunctionSet_Delay =>
        RS        <= LCD_CMDS(lcd_cmd_ptr)(9);
        RW        <= LCD_CMDS(lcd_cmd_ptr)(8);
        LCD_DB    <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
        activateW <= '0';
        if delayOK = '1' then
          stNext <= stDisplayCtrlSet;
        else
          stNext <= stFunctionSet_Delay;
        end if;

      --Issuse the display control set as follows
      --Display ON,  Cursor OFF, Blinking Cursor OFF.
      when stDisplayCtrlSet =>
        RS        <= LCD_CMDS(lcd_cmd_ptr)(9);
        RW        <= LCD_CMDS(lcd_cmd_ptr)(8);
        LCD_DB    <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
        activateW <= '1';
        stNext    <= stDisplayCtrlSet_Delay;

      --Gives the proper delay of 37us between the display control set
      --and the Display Clear command. 
      when stDisplayCtrlSet_Delay =>
        RS        <= LCD_CMDS(lcd_cmd_ptr)(9);
        RW        <= LCD_CMDS(lcd_cmd_ptr)(8);
        LCD_DB    <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
        activateW <= '0';
        if delayOK = '1' then
          stNext <= stDisplayClear;
        else
          stNext <= stDisplayCtrlSet_Delay;
        end if;

      --Issues the display clear command.
      when stDisplayClear =>
        RS        <= LCD_CMDS(lcd_cmd_ptr)(9);
        RW        <= LCD_CMDS(lcd_cmd_ptr)(8);
        LCD_DB    <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
        activateW <= '1';
        stNext    <= stDisplayClear_Delay;

      --Gives the proper delay of 1.52ms between the clear command
      --and the state where you are clear to do normal operations.
      when stDisplayClear_Delay =>
        RS        <= LCD_CMDS(lcd_cmd_ptr)(9);
        RW        <= LCD_CMDS(lcd_cmd_ptr)(8);
        LCD_DB    <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
        activateW <= '0';
        if delayOK = '1' then
          stNext <= stInitDne;
        else
          stNext <= stDisplayClear_Delay;
        end if;

      --State for normal operations for displaying characters, changing the
      --Cursor position etc.
      when stInitDne =>
        RS        <= LCD_CMDS(lcd_cmd_ptr)(9);
        RW        <= LCD_CMDS(lcd_cmd_ptr)(8);
        LCD_DB    <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
        activateW <= '0';
        stNext    <= stActWr;

      when stActWr =>
        RS        <= LCD_CMDS(lcd_cmd_ptr)(9);
        RW        <= LCD_CMDS(lcd_cmd_ptr)(8);
        LCD_DB    <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
        activateW <= '1';
        stNext    <= stCharDelay;

      --Provides a max delay between instructions.
      when stCharDelay =>
        RS        <= LCD_CMDS(lcd_cmd_ptr)(9);
        RW        <= LCD_CMDS(lcd_cmd_ptr)(8);
        LCD_DB    <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
        activateW <= '0';
        if delayOK = '1' then
          stNext <= stInitDne;
        else
          stNext <= stCharDelay;
        end if;
    end case;

  end process;

  --This process runs the write state machine
  process (oneUSClk, rst)
  begin
    if oneUSClk = '1' and oneUSClk'event then
      if rst = '1' then
        stCurW <= stIdle;
      else
        stCurW <= stNextW;
      end if;
    end if;
  end process;

  --This genearates the sequence of outputs needed to write to the LCD screen
  process (stCurW, activateW)
  begin

    case stCurW is
      --This sends the address across the bus telling the DIO5 that we are
      --writing to the LCD, in this configuration the adr_lcd(2) controls the
      --enable pin on the LCD
      when stRw =>
        OE      <= '0';
        --CS <= '0';
        --ADR2 <= '1';
        --ADR1 <= '0';
        stNextW <= stEnable;

      --This adds another clock onto the wait to make sure data is stable on 
      --the bus before enable goes low.  The lcd has an active falling edge 
      --and will write on the fall of enable
      when stEnable =>
        OE      <= '0';
        --CS <= '0';
        --ADR2 <= '0';
        --ADR1 <= '0';
        stNextW <= stIdle;

      --Waiting for the write command from the instuction state machine
      when stIdle =>
        --ADR2 <= '0';
        --ADR1 <= '0';
        --CS <= '1';
        OE <= '1';
        if activateW = '1' then
          stNextW <= stRw;
        else
          stNextW <= stIdle;
        end if;
    end case;
  end process;
  process(rst, oneUSClk, keyPressed, errorCount)
  begin
    if rst = '1' then
      show(0)    <= "10"&X"2E";
      show(1)    <= "10"&X"2E";
      show(2)    <= "10"&X"2E";
      show(3)    <= "10"&X"2E";
      show(4)    <= "10"&X"2E";
		show(5)    <= "10"&X"2E";			
      errorCount <= "0000";

    elsif oneUSClk = '1' and oneUSClk'event then
      if errorCount >= 5 then
        show(0) <= "10"&X"2E";
        show(1) <= "10"&X"2E";
        show(2) <= "10"&X"2E";
        show(3) <= "10"&X"2E";
		  show(4) <= "10"&X"2E";
        show(5) <= "10"&X"2E";
		  
      elsif keyPressed = '1' then
        case keyRead is
          when "00101100" =>      -- T                  
            show(0)      <= "10"&X"74";
            show(1 to 5) <= show(1 to 5);  
                                           
          when "00011100" =>        -- A    			 
			   show(0)      <= show(0);
            show(1)      <="10"&X"69";
            show(2 to 5) <= show(2 to 5);  
          when "01000100" =>     		-- O	 
			   show(0) <= show(0);
				show(1) <= show(1);
            show(2)      <="10"&X"6F";
            show(3 to 5) <= show(3 to 5);  
          when "01000010" =>      --K
			   show(0) <= show(0);
				show(1) <= show(1);
				show(2) <= show(2);
            show(3)      <= "10"&X"6E";
			  show(4 to 5) <= show(4 to 5);  
          when "00100100" =>      --E
			   show(0) <= show(0);
				show(1) <= show(1);
				show(2) <= show(2);
				show(3) <= show(3);
            show(4)      <="10"&X"65";
				  show(5) <= show(5);  
          when "00110101" =>      --Y
			   show(0) <= show(0);
				show(1) <= show(1);
				show(2) <= show(2);
				show(3) <= show(3);
				show(4) <= show(4);
            show(5)      <="10"&X"67";
  			 when others =>
				errorCount <= errorCount + 1;
				show <= show;
        end case;
        teclaLida <= '1';
      else
        show <= show;
      end if;
    end if;
  end process;

  process(oneUSClk, emptyBuf, teclaLida)
  begin
    if oneUSClk = '1' and oneUSClk'event then
      case actualState is
        when initRead =>
          if emptyBuf = '0' then
            actualState <= midRead;
          end if;
        when midRead =>
          if teclaLida <= '1' then
            actualState <= endRead;
          end if;
        when endRead =>
          actualState <= initRead;
      end case;
    end if;
  end process;

  process(oneUSClk)
  begin
    if oneUSClk = '1' and oneUSClk'event then
      case actualState is
        when initRead =>
          freeBuf <= '0';
        when midRead =>
          keyPressed <= '1';
          keyRead  <= keyBuf;
        when endRead =>
          keyPressed <= '0';
          teclaLida  <= '0';
          freeBuf    <= '1';
      end case;
    end if;
  end process;
end Behavioral;