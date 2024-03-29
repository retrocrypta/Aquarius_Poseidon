//============================================================================
//  Aquarius
// 
//  Enhanced version for MiSTer.
//  Copyright (C) 2017-2019 Sorgelig
//
//  Original Aquarius (c) 2016 Sebastien Delestaing 
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module guest_top(
	input         CLOCK_27,
`ifdef USE_CLOCK_50
	input         CLOCK_50,
`endif

// `ifdef XILINX
// 	output 		  CLOCK_50_buff,
// `endif

	output        LED,
	output [VGA_BITS-1:0] VGA_R,
	output [VGA_BITS-1:0] VGA_G,
	output [VGA_BITS-1:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,

`ifdef USE_HDMI
	output        HDMI_RST,
	output  [7:0] HDMI_R,
	output  [7:0] HDMI_G,
	output  [7:0] HDMI_B,
	output        HDMI_HS,
	output        HDMI_VS,
	output        HDMI_PCLK,
	output        HDMI_DE,
	inout         HDMI_SDA,
	inout         HDMI_SCL,
	input         HDMI_INT,
`endif

	input         SPI_SCK,
	inout         SPI_DO,
	input         SPI_DI,
	input         SPI_SS2,    // data_io
	input         SPI_SS3,    // OSD
	input         CONF_DATA0, // SPI_SS for user_io

`ifdef USE_QSPI
	input         QSCK,
	input         QCSn,
	inout   [3:0] QDAT,
`endif
`ifndef NO_DIRECT_UPLOAD
	input         SPI_SS4,
`endif

	output [12:0] SDRAM_A,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nWE,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nCS,
	output  [1:0] SDRAM_BA,
	output        SDRAM_CLK,
	output        SDRAM_CKE,

`ifdef DUAL_SDRAM
	output [12:0] SDRAM2_A,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_DQML,
	output        SDRAM2_DQMH,
	output        SDRAM2_nWE,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nCS,
	output  [1:0] SDRAM2_BA,
	output        SDRAM2_CLK,
	output        SDRAM2_CKE,
`endif

	output        AUDIO_L,
	output        AUDIO_R,
`ifdef I2S_AUDIO
	output        I2S_BCK,
	output        I2S_LRCK,
	output        I2S_DATA,
`endif
`ifdef SPDIF_AUDIO
	output        SPDIF,
`endif
`ifdef USE_AUDIO_IN
	input         AUDIO_IN,
`endif
	input         UART_RX,
	output        UART_TX

);

`ifdef NO_DIRECT_UPLOAD
localparam bit DIRECT_UPLOAD = 0;
wire SPI_SS4 = 1;
`else
localparam bit DIRECT_UPLOAD = 1;
`endif

`ifdef USE_QSPI
localparam bit QSPI = 1;
assign QDAT = 4'hZ;
`else
localparam bit QSPI = 0;
`endif

`ifdef VGA_8BIT
localparam VGA_BITS = 8;
`else
localparam VGA_BITS = 6;
`endif

`ifdef USE_HDMI
localparam bit HDMI = 1;
assign HDMI_RST = 1'b1;
`else
localparam bit HDMI = 0;
`endif

`ifdef BIG_OSD
localparam bit BIG_OSD = 1;
`define SEP "-;",
`else
localparam bit BIG_OSD = 0;
`define SEP
`endif

`ifdef USE_AUDIO_IN
wire TAPE_SOUND = AUDIO_IN;
`else
wire TAPE_SOUND = UART_RX;
`endif


assign LED    = ioctl_download | tape_req;

`include "build_id.v"

localparam CONF_STR =
{
	"AQUARIUS;;",
	"F,BIN,Load Cartridge;",
	"F,CAQ,Load Tape;",
	"O9,Fast loading,No,Yes;",
	"O24,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"O56,CPU Speed,Normal,x2,x4,x8;",
	"O78,RAM expansion,16KB,32KB,None,4KB;",
	"T0,Reset;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys;
wire pll_locked;

pll pll
(
	.inclk0(CLOCK_27),
	.areset(0),
	.c0(clk_sys),
	.locked(pll_locked),
);

reg ce_3m5;
reg ce_1m7;
reg ce_3k33;

wire fast_tape = tape_req && {status[9],status[6:5]};

always @(negedge clk_sys) begin	
	reg  [4:0] clk_div;
	reg [14:0] clk_div2;

	clk_div <= clk_div + 1'd1;
	ce_1m7 <= !clk_div[4:0];
	
	casex({fast_tape, status[6:5]}) 
		'b1XX: ce_3m5 <= 1;
		'b000: ce_3m5 <= !clk_div[3:0];
		'b001: ce_3m5 <= !clk_div[2:0];
		'b010: ce_3m5 <= !clk_div[1:0];
		'b011: ce_3m5 <= !clk_div[0:0];
	endcase
	
	clk_div2 <= clk_div2 + 1'd1;
	if(clk_div2 >= (fast_tape ? 1073 : 17187)) clk_div2 <= 0;
	ce_3k33 <= !clk_div2;
end

//////////////////   HPS I/O   ///////////////////
wire [10:0] ps2_key;

wire [15:0] joystick_0;
wire [15:0] joystick_1;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire [31:0] status;

wire ypbpr;

wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire        ioctl_download;
wire  [7:0] ioctl_index;

///////////////////////////////////////////////

wire no_csync;

user_io #(.STRLEN($size(CONF_STR)>>3), .SD_IMAGES(2), .FEATURES(32'h0 | (BIG_OSD << 13) | (HDMI << 14))) user_io
(	
	.clk_sys        	(clk_sys         	),
	.clk_sd           (clk_sys           ),
	.conf_str       	(CONF_STR       	),
	.SPI_CLK        	(SPI_SCK        	),
	.SPI_SS_IO      	(CONF_DATA0     	),
	.SPI_MISO       	(SPI_DO        	),
	.SPI_MOSI       	(SPI_DI         	),
	.buttons        	(buttons        	),
	.scandoubler_disable (forced_scandoubler),
	.ypbpr          	(ypbpr          	),
	.no_csync         (no_csync         ),
	.key_strobe     	(key_strobe     	),
	.key_pressed    	(key_pressed    	),
	.key_extended   	(key_extended   	),
	.key_code       	(key_code       	),
	.joystick_0       ( joystick_0      ),
	.joystick_1       ( joystick_1      ),
	.status         	(status         	),
);

data_io data_io(
	.clk_sys       ( clk_sys      ),
	.SPI_SCK       ( SPI_SCK      ),
	.SPI_SS2       ( SPI_SS2      ),
	.SPI_DI        ( SPI_DI       ),
	.clkref_n      ( 1'b0         ),
	.ioctl_download( ioctl_download),
	.ioctl_index   ( ioctl_index  ),
	.ioctl_wr      ( ioctl_wr     ),
	.ioctl_addr    ( ioctl_addr   ),
	.ioctl_dout    ( ioctl_dout   )
);

///////////////////////////////////////////////

wire reset = status[0] | buttons[1] | !pll_locked;
wire cpu_reset = reset || (ioctl_download && (ioctl_index == 1));

reg rom_loaded = 0;
always @(posedge clk_sys) begin
	if(ioctl_download && (ioctl_index == 1)) rom_loaded <= 1;
	if(reset) rom_loaded <= 0;
end

// CPU control signals
wire [15:0] cpu_addr;
wire [7:0] cpu_din;
wire [7:0] cpu_dout;
wire cpu_rd_n;
wire cpu_wr_n;
wire cpu_mreq_n;
wire cpu_m1_n;
wire cpu_iorq_n;

T80s T80s
(
	.RESET_n  ( !cpu_reset ),
	.CLK      ( clk_sys    ),
	.CEN      ( ce_3m5     ),
	.IORQ_n   ( cpu_iorq_n ),
	.M1_n		 ( cpu_m1_n   ),
	.MREQ_n   ( cpu_mreq_n ),
	.RD_n     ( cpu_rd_n   ), 
	.WR_n     ( cpu_wr_n   ),
	.A        ( cpu_addr   ),
	.DI       ( cpu_din    ),
	.DO       ( cpu_dout   )
);

wire [7:0] aquarius_rom_data;
main_rom main_rom
(
	.clk  ( clk_sys           ),
	.addr ( cpu_addr[12:0]    ),
	.data ( aquarius_rom_data )
);

wire       ram_we, ext_we;
wire [7:0] ram_dout, ram_din;
gen_dpram #(16,8) main_ram
(
	.clock_a(clk_sys),
	.address_a({2'b11, ioctl_addr[13:0]}),
	.data_a(ioctl_dout),
	.wren_a((ioctl_index == 1) && ioctl_download && ioctl_wr),

	.clock_b(clk_sys),
	.address_b(cpu_addr),
	.data_b(ram_din),
	.enable_b(ce_3m5),
	.wren_b(ram_we | ext_we),
	.q_b(ram_dout)
);

wire video_we;
wire cass_in, cass_out;
Pla1 Pla1
(
	.CLK          ( clk_sys & ce_3m5 ),
	.RST          ( cpu_reset   ),
	
	.CFG          ( status[8:7] + 2'd2 ),

	.ADDR         ( cpu_addr    ),
	.CPU_IN       ( cpu_dout    ),	 
	.CPU_OUT      ( cpu_din     ),
	.MEMWR        (  !cpu_mreq_n              && !cpu_wr_n ), 
	.IOWR         ( (!cpu_iorq_n && cpu_m1_n) && !cpu_wr_n ),
	.IORD         ( (!cpu_iorq_n && cpu_m1_n) && !cpu_rd_n ),

	.VIDEO_WE     ( video_we    ),

	.DATA_ROM     ( aquarius_rom_data ),
	.DATA_ROMPACK ( ram_dout    ),
	.ROM_EN       ( rom_loaded  ),

	.EXT_WE       ( ext_we      ),
	.RAM_WE       ( ram_we      ),
	.RAM_IN       ( ram_dout    ),
	.RAM_OUT      ( ram_din     ),

	.KEY_VALUE    ( key_value   ),
	.PSG_IN       ( psg_dout    ),
	.PSG_SEL      ( psg_sel     ),
	.LED_OUT      (  ),
	.CASS_OUT     ( cass_out    ),
	.CASS_IN      ( cass_in     ),
	.VSYNC        ( vf          )
);

////////////////////////////////////////////////////////

gen_dpram #(10,8) video_data
(
	.clock_a   ( clk_sys   ),
	.enable_a  ( ce_3m5    ),
	.address_a ( cpu_addr[9:0]),
	.wren_a    (~cpu_addr[10] & video_we ),
	.data_a    ( cpu_dout  ),

	.clock_b   ( clk_sys   ),
	.address_b ( vd_addr   ),
	.q_b       ( vd_data   )
);

gen_dpram #(10,8) video_color
(
	.clock_a   ( clk_sys   ),
	.enable_a  ( ce_3m5    ),
	.address_a ( cpu_addr[9:0]),
	.wren_a    ( cpu_addr[10] & video_we ),
	.data_a    ( cpu_dout  ),

	.clock_b   ( clk_sys   ),
	.address_b ( vd_addr   ),
	.q_b       ( vd_color  )
);

wire [7:0] vd_data, vd_color;
wire [9:0] vd_addr;



wire [2:0] scale = status[4:2];


wire vf;
video video
(
	.*,
	.video_addr(vd_addr),
	.video_data(vd_data),
	.video_color(vd_color)
);

wire [7:0] R,G,B;
wire HBlank,VBlank,HSync,VSync;
wire ce_pix;

mist_video #(.COLOR_DEPTH(6), .SD_HCNT_WIDTH(11), .USE_BLANKS(1),.OUT_COLOR_DEPTH(VGA_BITS), .BIG_OSD(BIG_OSD)) mist_video (	
	.clk_sys      (clk_sys     ),
	.SPI_SCK      (SPI_SCK    ),
	.SPI_SS3      (SPI_SS3    ),
	.SPI_DI       (SPI_DI     ),
	.R            (R[7:2]),
	.G            (G[7:2]),
	.B            (B[7:2]),
	.HSync        (HSync      ),
	.VSync        (VSync      ),
	.HBlank       (HBlank     ),
	.VBlank       (VBlank     ),
	.VGA_R        (VGA_R      ),
	.VGA_G        (VGA_G      ),
	.VGA_B        (VGA_B      ),
	.VGA_VS       (VGA_VS     ),
	.VGA_HS       (VGA_HS     ),
	.ce_divider   (1'b1       ),
	.no_csync     ( no_csync  ),
	.scandoubler_disable(forced_scandoubler),
	.scanlines    (forced_scandoubler ? 2'b00 : {scale==3, scale==2}),
	.ypbpr        ( ypbpr     )
	);

//video_mixer #(.LINE_LENGTH(320)) video_mixer
//(
//	.*,
//   .ce_pix_actual(ce_pix),
//	.scanlines(forced_scandoubler ? 2'b00 : {scale==3, scale==2}),
//	.scandoubler_disable(forced_scandoubler),
//   .mono(0),
//   .ypbpr_full(1),
//   .line_start(HBlank),
//	.HSync (HSync),
//	.VSync (VSync),
//
//	.R (R[7:2]),
//	.G (G[7:2]),
//	.B (B[7:2]),
//	
//	.hq2x(scale == 1)
//);

////////////////////////////////////////////////////////

wire [7:0] psg_dout;
wire       psg_sel;
wire [9:0] audio_a,audio_b,audio_c;

ym2149 ym2149
(
	.CLK(clk_sys),
	.CE(ce_1m7),
	.RESET(cpu_reset),

	.BDIR(psg_sel && !cpu_wr_n),
	.BC(psg_sel && (cpu_addr[0] || cpu_wr_n)),
	.DI(cpu_dout),
	.DO(psg_dout),

	.CHANNEL_A(audio_a[7:0]),
	.CHANNEL_B(audio_b[7:0]),
	.CHANNEL_C(audio_c[7:0]),

	.SEL(0),
	.MODE(0),

	.IOA_in(pad0),
	.IOB_in(pad1)
);

assign {audio_a[9:8],audio_b[9:8],audio_c[9:8]} = 0;
wire [9:0] audio_data = audio_a+audio_b+audio_c+{2'b00,cass_out,cass_in,6'd0};


wire signed [15:0] DAC_L,DAC_R;

assign DAC_L = {audio_data, 6'd0};
assign DAC_R = {audio_data, 6'd0};

`ifdef I2S_AUDIO

wire [31:0] clk_rate =  32'd57_272_727;
i2s i2s (
	.reset(1'b0),
	.clk(clk_sys),
	.clk_rate(clk_rate),

	.sclk(I2S_BCK),
	.lrclk(I2S_LRCK),
	.sdata(I2S_DATA),

	.left_chan (DAC_L),
	.right_chan(DAC_R)
);
`endif


dac #(10) dac_l (
   .clk_i        (clk_sys),
   .res_n_i      (1      ),
   .dac_i        (audio_data),
   .dac_o        (AUDIO_L)
);
assign AUDIO_R=AUDIO_L;


////////////////////////////////////////////////////////

wire [7:0] pad0, pad1;

pad pad_0(.joy_in(joystick_0[9:0]), .pad_out(pad0 | kbd_pad0));
pad pad_1(.joy_in(joystick_1[9:0]), .pad_out(pad1 | kbd_pad1));

// include keyboard decoder
wire [7:0] key_value; // Pla1 <-> PS2_to_matrix

wire [9:0] kbd_pad0,kbd_pad1;
wire        key_pressed;
wire [7:0]  key_code;
wire        key_strobe;
wire        key_extended;

PS2_to_matrix PS2_to_matrix
(
	.clk   ( clk_sys   ),
	.reset ( cpu_reset ),

	// Pla1 interface
	.sfrdatao ( key_value      ),
	.addr     ( cpu_addr[15:8] ),

	.pad0(kbd_pad0),
	.pad1(kbd_pad1),
	
	.psdatai(key_code),
	.psdataex(key_extended),
	.pspress(key_pressed),
	.psstate(key_strobe)
);

////////////////////////////////////////////////////////

reg tape_loaded = 0;
always @(posedge clk_sys) begin
	reg old_download;
	old_download <= ioctl_download;
	
	tape_loaded <= (old_download & ~ioctl_download && (ioctl_index == 2));
	if(cpu_reset) tape_loaded <= 0;
end

gen_dpram #(16,8) tape_ram
(
	.clock_a(clk_sys),
	.address_a(ioctl_addr[15:0]),
	.data_a(ioctl_dout),
	.wren_a((ioctl_index == 2) && ioctl_download && ioctl_wr),

	.clock_b(clk_sys),
	.address_b(tape_addr),
	.data_b(0),
	.wren_b(0),
	.q_b(tape_data)
);

wire [7:0]  tape_data;
wire [15:0] tape_addr;
wire        tape_req;

tape tape
(
	.clk		( clk_sys      ),
	.ce_tape ( ce_3k33      ),
	.reset	( cpu_reset	   ),

	// Memory interface
	.data 	( tape_data 	),
	.addr		( tape_addr		),
	.length	( ioctl_addr[15:0]),
	.req     ( tape_req     ),

	// Tape interface
	.loaded	( tape_loaded	),
	.out		( cass_in	   )
);

endmodule
