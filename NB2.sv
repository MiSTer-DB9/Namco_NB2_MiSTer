//============================================================================
//
//  Namco NB-2 MiSTer core -- top level (emu).
//  Copyright (C) 2026 Kyle Lester
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation, either version 3 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program.  If not, see <https://www.gnu.org/licenses/>.
//
//  Structure follows MiSTer-devel/Template_MiSTer (Template.sv, GPL-2.0+) and the
//  author's Namco NB-1 core (NB1.sv).
//
//============================================================================
//
// MiSTer glue around rtl/nb2/nb2_core.sv (the NB-2 board): hps_io, the 96.768 MHz PLL, the OSD, CRT Adjust and
// the framework video/audio paths. Both NB-2 games are ROT0 288 x 224. The DDR3 port carries the sprite-graphics
// store (docs/ARCHITECTURE.md) and, for the OSD Orientation Vertical CW/CCW, screen_rotate's framebuffer writes.

module emu
(
    //Master input clock
    input         CLK_50M,

    //Async reset from top-level module.
    //Can be used as initial reset.
    input         RESET,

    //Must be passed to hps_io module
    inout  [45:0] HPS_BUS,

    //Base video clock. Usually equals to CLK_SYS.
    output        CLK_VIDEO,

    //Multiple resolutions are supported using different CE_PIXEL rates.
    //Must be based on CLK_VIDEO
    output        CE_PIXEL,

    //Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
    //if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
    output [12:0] VIDEO_ARX,
    output [12:0] VIDEO_ARY,

    output  [7:0] VGA_R,
    output  [7:0] VGA_G,
    output  [7:0] VGA_B,
    output        VGA_HS,
    output        VGA_VS,
    output        VGA_DE,    // = ~(VBlank | HBlank)
    output        VGA_F1,
    output [1:0]  VGA_SL,
    output        VGA_SCALER, // Force VGA scaler
    output        VGA_DISABLE, // analog out is off

    input  [11:0] HDMI_WIDTH,
    input  [11:0] HDMI_HEIGHT,
    output        HDMI_FREEZE,
    output        HDMI_BLACKOUT,
    output        HDMI_BOB_DEINT,

`ifdef MISTER_FB
    // Use framebuffer in DDRAM (USE_FB=1 in qsf)
    // FB_FORMAT:
    //    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
    //    [3]   : 0=16bits 565 1=16bits 1555
    //    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
    //
    // FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
    output        FB_EN,
    output  [4:0] FB_FORMAT,
    output [11:0] FB_WIDTH,
    output [11:0] FB_HEIGHT,
    output [31:0] FB_BASE,
    output [13:0] FB_STRIDE,
    input         FB_VBL,
    input         FB_LL,
    output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
    // Palette control for 8bit modes.
    // Ignored for other video modes.
    output        FB_PAL_CLK,
    output  [7:0] FB_PAL_ADDR,
    output [23:0] FB_PAL_DOUT,
    input  [23:0] FB_PAL_DIN,
    output        FB_PAL_WR,
`endif
`endif

    output        LED_USER,  // 1 - ON, 0 - OFF.

    // b[1]: 0 - LED status is system status OR'd with b[0]
    //       1 - LED status is controled solely by b[0]
    // hint: supply 2'b00 to let the system control the LED.
    output  [1:0] LED_POWER,
    output  [1:0] LED_DISK,

    // I/O board button press simulation (active high)
    // b[1]: user button
    // b[0]: osd button
    output  [1:0] BUTTONS,

    input         CLK_AUDIO, // 24.576 MHz
    output [15:0] AUDIO_L,
    output [15:0] AUDIO_R,
    output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
    output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

    //ADC
    inout   [3:0] ADC_BUS,

    //SD-SPI
    output        SD_SCK,
    output        SD_MOSI,
    input         SD_MISO,
    output        SD_CS,
    input         SD_CD,

    //High latency DDR3 RAM interface
    //Use for non-critical time purposes
    output        DDRAM_CLK,
    input         DDRAM_BUSY,
    output  [7:0] DDRAM_BURSTCNT,
    output [28:0] DDRAM_ADDR,
    input  [63:0] DDRAM_DOUT,
    input         DDRAM_DOUT_READY,
    output        DDRAM_RD,
    output [63:0] DDRAM_DIN,
    output  [7:0] DDRAM_BE,
    output        DDRAM_WE,

    //SDRAM interface with lower latency
    output        SDRAM_CLK,
    output        SDRAM_CKE,
    output [12:0] SDRAM_A,
    output  [1:0] SDRAM_BA,
    inout  [15:0] SDRAM_DQ,
    output        SDRAM_DQML,
    output        SDRAM_DQMH,
    output        SDRAM_nCS,
    output        SDRAM_nCAS,
    output        SDRAM_nRAS,
    output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
    //Secondary SDRAM
    //Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
    input         SDRAM2_EN,
    output        SDRAM2_CLK,
    output [12:0] SDRAM2_A,
    output  [1:0] SDRAM2_BA,
    inout  [15:0] SDRAM2_DQ,
    output        SDRAM2_nCS,
    output        SDRAM2_nCAS,
    output        SDRAM2_nRAS,
    output        SDRAM2_nWE,
`endif

    input         UART_CTS,
    output        UART_RTS,
    input         UART_RXD,
    output        UART_TXD,
    output        UART_DTR,
    input         UART_DSR,

    // Open-drain User port.
    // 0 - D+/RX
    // 1 - D-/TX
    // 2..6 - USR2..USR6
    // Set USER_OUT to 1 to read from USER_IN.
	output			USER_OSD,
	// [MiSTer-DB9 BEGIN] - DB9/SNAC8 support: per-pin push-pull mask
	output	[7:0] USER_PP,
	// [MiSTer-DB9 END]
	input		[7:0] USER_IN,
	output		[7:0] USER_OUT,	

    input         OSD_STATUS
);

// [MiSTer-DB9 BEGIN] - DB9/SNAC8 support: USER_PP default (port_batch replaces with USER_PP_DRIVE)
assign USER_PP = USER_PP_DRIVE;
// [MiSTer-DB9 END]
// [MiSTer-DB9 BEGIN] - DB9/SNAC8 support: joydb wrapper
wire         CLK_JOY = CLK_50M;                 // Assign clock between 40-50Mhz
wire   [1:0] joy_type        = status[127:126]; // 0=Off, 1=Saturn, 2=DB9MD, 3=DB15
wire         joy_2p          = status[125];
wire         joy_db9md_en    = (joy_type == 2'd2);
wire         joy_db15_en     = (joy_type == 2'd3);
wire         joy_any_en      = |joy_type;
// Legacy 3-bit alias for fork-specific MT32 / SNAC fallback code. Non-canonical
// RHS variants (ext_iec_en, mt32_disable) need a hand-port — alias is raw.
wire   [2:0] JOY_FLAG        = {joy_db9md_en, joy_db15_en, joy_2p};
// [MiSTer-DB9 END]

// [MiSTer-DB9-Pro BEGIN] - Saturn key gate
wire         saturn_unlocked;                   // driven by hps_io UIO_DB9_KEY (0xFE)
// [MiSTer-DB9-Pro END]

// [MiSTer-DB9 BEGIN] - DB9/SNAC8 support: joydb wrapper wires + instance
wire   [7:0] USER_OUT_DRIVE;
wire   [7:0] USER_PP_DRIVE;
wire  [15:0] joydb_1, joydb_2;
wire         joydb_1ena, joydb_2ena;
wire  [15:0] joy_raw_payload;
wire  [31:0] joystick_0_USB, joystick_1_USB;

// [MiSTer-DB9 BEGIN] - DB9/SNAC8 support: probe-gating wires
// SNAC cores: replace 1'b0 with the core's SNAC enable expression so SNAC
// preempts the joydb wrapper on shared USER_IO pins. Default 1'b0 is no-op.
wire         snac_active     = 1'b0;
// MT32-pi probe-suppression gate. Auto-detected from MT32 signals declared
// elsewhere in this file (mt32_disable / mt32_use / mt32_on_primary). Hand-edit
// if the heuristic missed your core's gate expression. Suppresses the OSD-open
// autodetect probe so it doesn't read the RPi's I2C master traffic as a ghost
// Saturn signature. See the fork hazard notes.
wire         mt32_primary_active = 1'b0;
// [MiSTer-DB9 END]
// [MiSTer-DB9 BEGIN] - DB9 programmable-remap matrix wires
// joydb_*_mapped = MiSTer-standard joystick words (consumed in Layer B);
// db9_remap_* = 0xFD selector stream driven by the hps_io instance.
wire  [15:0] joydb_1_mapped, joydb_2_mapped;
wire         db9_remap_cmd;
wire   [5:0] db9_remap_byte_cnt;
wire  [15:0] db9_remap_din;
// [MiSTer-DB9 END]
// [MiSTer-DB9 BEGIN] - DB9 remap factory default (used until Main_MiSTer streams UIO 0xFD)
// Derived from CONF_STR J1, same rule as db9_map.cpp; lets the core work on a stock MiSTer binary.
// DB15:  Button 1=A, Button 2=B, Button 3=C, Start=START, Coin=SELECT, Service=D
// DB9MD: Button 1=A, Button 2=B, Button 3=C, Start=START, Coin=MODE, Service=X
wire  [35:0] db9_remap_default_db15  = 36'hFFF7BA654;
wire  [35:0] db9_remap_default_db9md = 36'hFFF7BA654;
// [MiSTer-DB9 END]
joydb joydb (
  .clk             ( CLK_JOY         ),
  .clk_sys         ( clk_sys            ),
  .USER_IN         ( USER_IN         ),
  .OSD_STATUS          ( OSD_STATUS          ),
  .snac_active         ( snac_active         ),
  .mt32_primary_active ( mt32_primary_active ),
  .joy_type        ( joy_type        ),
  .joy_2p          ( joy_2p          ),
  .saturn_unlocked ( saturn_unlocked ),
  .USER_OUT_DRIVE  ( USER_OUT_DRIVE  ),
  .USER_PP_DRIVE   ( USER_PP_DRIVE   ),
  .USER_OSD        ( USER_OSD        ),
  .joydb_1         ( joydb_1         ),
  .joydb_2         ( joydb_2         ),
  .joydb_1ena      ( joydb_1ena      ),
  .joydb_2ena      ( joydb_2ena      ),
  .remap_cmd       ( db9_remap_cmd      ),
  .remap_byte_cnt  ( db9_remap_byte_cnt ),
  .remap_din       ( db9_remap_din      ),
  .remap_default_db15  ( db9_remap_default_db15  ),
  .remap_default_db9md ( db9_remap_default_db9md ),
  .joydb_1_mapped  ( joydb_1_mapped     ),
  .joydb_2_mapped  ( joydb_2_mapped     ),
  .joy_raw         ( joy_raw_payload )
);

assign USER_OUT = USER_OUT_DRIVE;
// [MiSTer-DB9 END]
// [MiSTer-DB9 BEGIN] - DB9/SNAC8 support: DB9 pads override USB P1/P2
assign joystick_0 = joydb_1ena ? (OSD_STATUS ? 32'b0 : joydb_1_mapped[9:0]) : joystick_0_USB;
assign joystick_1 = joydb_2ena ? (OSD_STATUS ? 32'b0 : joydb_2_mapped[9:0]) : joydb_1ena ? joystick_0_USB : joystick_1_USB;
// [MiSTer-DB9 END]

assign ADC_BUS  = 'Z;
// [MiSTer-DB9 BEGIN] - USER_OUT driven by the joydb wrapper above
//assign USER_OUT = '1;
// [MiSTer-DB9 END]
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;
assign AUDIO_S = 1;
assign LED_POWER = 0;
assign BUTTONS = 0;

// 288x224 on a 4:3 screen; turned 90 degrees (Vertical CW/CCW) it is 3:4.
wire [1:0] ar = status[122:121];
wire       video_rotated;
assign VIDEO_ARX = (!ar) ? (video_rotated ? 12'd3 : 12'd4) : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? (video_rotated ? 12'd4 : 12'd3) : 12'd0;

// Orientation (one OSD item, as the NB-1 core and the NA-1/NA-2 core), status[14:13]:
//   orient  OSD label      HDMI/scaler     native (analog)  no_rotate rotate_ccw osd_flip
//   00      Horizontal     H               H                1         x          0
//   01      Vertical CCW   H rot 90 CCW    H                0         1          0
//   10      Vertical CW    H rot 90 CW     H                0         0          0
//   11      Flipped        H rot 180       H rot 180        1         x          1
// Vertical CW/CCW are the framework's screen_rotate (DDR3 framebuffer -> HDMI scaler; Direct Video bypasses
// them); Flipped is made by the core's renderers (nb2_core osd_flip), so it reaches the 15 kHz output too.
wire [1:0] orient     = status[14:13];
wire       rot_vert   = (orient == 2'd1) || (orient == 2'd2);
wire       no_rotate  = !rot_vert || direct_video;
wire       rotate_ccw = (orient == 2'd1);
wire       osd_flip   = (orient == 2'd3);

`include "build_id.v"
// Status bits: 0 Reset, 1 Re-run ROM check, 4 ROM cache off (diagnostic), 5 Service mode, 10:9 Stereo mix,
// 12:11 Scandoubler Fx, 14:13 Orientation, 122:121 Aspect ratio; CRT Adjust as the NB-1 core: 96 On, 104:101 H-Position,
// 108:105 V-Shift, 116:112 H-Size (H1 hides the amounts while CRT Adjust is Off).
localparam CONF_STR = {
	"NB2;;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O[14:13],Orientation,Horizontal,Vertical CCW,Vertical CW,Flipped;",
	"O[12:11],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%;",
	"-;",
	"P1,CRT Adjust;",
	"P1O[96],CRT Adjust,Off,On;",
	"H1P1O[116:112],CRT H-Size,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"H1P1O[104:101],CRT H-Position,0,+6,+12,+18,+24,+30,+36,+42,-48,-42,-36,-30,-24,-18,-12,-6;",
	"H1P1O[108:105],CRT V-Shift,0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
	"-;",
	"O[5],Service mode (SW1-1),Off,On;",
	"-;",
	"O[10:9],Stereo mix,None,25%,50%,100%;",
	"-;",
	// [MiSTer-DB9-Pro BEGIN] - Saturn-first joy_type (canonical bit notation)
	"O[127:126],UserIO Joystick,Off,Saturn,DB9MD,DB15;",
	"O[125],UserIO Players, 1 Player,2 Players;",
	// [MiSTer-DB9-Pro END]
	"-;",
	"T[0],Reset;",
	"T[1],Re-run ROM check;",
	"R[0],Reset and close OSD;",
	"-;",
	"J1,Button 1,Button 2,Button 3,Start,Coin,Service;",
	"jn,A,B,X,Start,Select,R;",
	"v,0;",
	"V,v",`BUILD_DATE
};

wire         forced_scandoubler, direct_video;
wire  [21:0] gamma_bus;
wire   [1:0] buttons;
wire [127:0] status;
wire  [31:0] joystick_0, joystick_1, joystick_2, joystick_3;

wire        ioctl_download, ioctl_wr, ioctl_wait, ioctl_upload, ioctl_rd, ioctl_upload_req;
wire [15:0] ioctl_index, ioctl_dout, ioctl_din;
wire [26:0] ioctl_addr;

hps_io #(.CONF_STR(CONF_STR), .WIDE(1)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),
	.forced_scandoubler(forced_scandoubler),
	.direct_video(direct_video),
	.video_rotated(video_rotated),
	.buttons(buttons),
	.status(status),
	.status_menumask({14'd0, ~status[96], 1'b0}),
	// [MiSTer-DB9 BEGIN] - DB9/SNAC8 support: joy_raw
	.joy_raw(joy_raw_payload),
	// programmable remap matrix selector load (UIO_DB9_MAP 0xFD)
	.db9_remap_cmd(db9_remap_cmd),
	.db9_remap_byte_cnt(db9_remap_byte_cnt),
	.db9_remap_din(db9_remap_din),
	// [MiSTer-DB9 END]
	// [MiSTer-DB9-Pro BEGIN] - Saturn key gate
	.saturn_unlocked(saturn_unlocked),
	// [MiSTer-DB9-Pro END]
	// [MiSTer-DB9 BEGIN] - USB joysticks routed through the DB9 override
	.joystick_0(joystick_0_USB),
	.joystick_1(joystick_1_USB),
	// [MiSTer-DB9 END]
	.joystick_2(joystick_2),
	.joystick_3(joystick_3),
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait),
	.ioctl_upload(ioctl_upload),
	.ioctl_upload_req(ioctl_upload_req),
	.ioctl_upload_index(8'd1),
	.ioctl_din(ioctl_din),
	.ioctl_rd(ioctl_rd)
);

///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys;      // 96.768 MHz = 2 x the 48.384 MHz NB-2 master oscillator
wire pll_locked;
nb1_pll pll (.refclk(CLK_50M), .rst(1'b0), .clk_sys(clk_sys), .locked(pll_locked));

///////////////////////   NB-2 BOARD   ///////////////////////////

reg pcache_bypass = 1'b0;
always @(posedge clk_sys) pcache_bypass <= status[4];

wire        ce_pix, hblank, vblank, hsync, vsync, line_end, frame_end, rom_loading, cpu_running;
wire [7:0]  core_r, core_g, core_b;
wire [8:0]  hcount, vcount;
wire signed [15:0] snd_l, snd_r;

nb2_core core
(
	.clk_sys(clk_sys),
	.pll_locked(pll_locked),
	.reset_request(RESET | status[0] | buttons[1]),
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait),
	.ioctl_upload(ioctl_upload),
	.ioctl_rd(ioctl_rd),
	.ioctl_din(ioctl_din),
	.ioctl_upload_req(ioctl_upload_req),
	.joy0(joystick_0), .joy1(joystick_1), .joy2(joystick_2), .joy3(joystick_3),
	.sw_service(status[5]),
	.rerun_check(status[1]),
	.pcache_bypass(pcache_bypass),
	.osd_flip(osd_flip),
	.SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH), .SDRAM_BA(SDRAM_BA),
	.SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS),
	.SDRAM_CKE(SDRAM_CKE), .SDRAM_CLK(SDRAM_CLK),
	.DDRAM_BUSY(obj_busy), .DDRAM_BURSTCNT(), .DDRAM_ADDR(obj_addr), .DDRAM_DOUT(DDRAM_DOUT),
	.DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(obj_rd), .DDRAM_DIN(obj_din), .DDRAM_BE(obj_be),
	.DDRAM_WE(obj_we),
	.ce_pix(ce_pix), .r(core_r), .g(core_g), .b(core_b), .hblank(hblank), .vblank(vblank), .hsync(hsync),
	.vsync(vsync), .hcount(hcount), .vcount(vcount), .line_end(line_end), .frame_end(frame_end),
	.audio_l(snd_l), .audio_r(snd_r),
	.rom_loading(rom_loading), .cpu_running(cpu_running), .chk_done(), .chk_pass(), .game_rot(),
	.dbg_cpu_pc(), .dbg_c75_pc(), .dbg_unmap_reads(), .dbg_tile_under(), .dbg_roz_under(), .dbg_spr_drops(), .dbg_wram_sdram()
);
assign DDRAM_CLK = clk_sys;

// DDR3: the sprite store (reads, ROM-load writes) and screen_rotate's framebuffer writes (Vertical CW/CCW)
wire        obj_busy, obj_rd, obj_we, sr_we;
wire [28:0] obj_addr, sr_addr;
wire [63:0] obj_din, sr_din;
wire  [7:0] obj_be, sr_be;
nb2_ddr_mux ddr_mux
(
	.clk(clk_sys),
	.a_rd(obj_rd), .a_we(obj_we), .a_addr(obj_addr), .a_din(obj_din), .a_be(obj_be), .a_busy(obj_busy),
	.b_we(sr_we), .b_addr(sr_addr), .b_din(sr_din), .b_be(sr_be),
	.DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR), .DDRAM_DIN(DDRAM_DIN),
	.DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE), .DDRAM_RD(DDRAM_RD),
	.b_overflows()
);

assign AUDIO_L   = snd_l;
assign AUDIO_R   = snd_r;
assign AUDIO_MIX = status[10:9];

///////////////////////   VIDEO   //////////////////////////////

wire        av_ce, av_hb, av_vb, av_hs, av_vs;
wire [23:0] av_rgb;
nb1_crt_adjust crt_adjust
(
	.clk_sys(clk_sys),
	.ce_pix(ce_pix),
	.frame_event(frame_end),
	.osd_on(status[96]),
	.osd_hsize(status[116:112]),
	.osd_hpos(status[104:101]),
	.osd_vshift(status[108:105]),
	.sd_off((status[12:11] == 2'd0) && !forced_scandoubler),
	.vb_next((vcount == 9'd263) ? 1'b0 : (vcount >= 9'd223)),
	.rgb_in({core_r, core_g, core_b}),
	.hblank_in(hblank),
	.vblank_in(vblank),
	.hsync_in(hsync),
	.vsync_in(vsync),
	.ce_out(av_ce),
	.rgb_out(av_rgb),
	.hblank_out(av_hb),
	.vblank_out(av_vb),
	.hsync_out(av_hs),
	.vsync_out(av_vs),
	.active(),
	.hsize_s(),
	.hpos_s(),
	.vsh_s()
);

arcade_video #(.WIDTH(288), .DW(24), .GAMMA(1)) arcade_video
(
	.clk_video(clk_sys),
	.ce_pix(av_ce),
	.RGB_in(av_rgb),
	.HBlank(av_hb),
	.VBlank(av_vb),
	.HSync(av_hs),
	.VSync(av_vs),
	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_HS(VGA_HS),
	.VGA_VS(VGA_VS),
	.VGA_DE(VGA_DE),
	.VGA_SL(VGA_SL),
	.fx({1'b0, status[12:11]}),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus)
);

// Orientation Vertical CW/CCW: the framework framebuffer rotation (HDMI/scaler only). Its DDR3 writes go through
// nb2_ddr_mux (above); Horizontal and Flipped keep it idle (FB_EN low).
screen_rotate screen_rotate
(
	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_HS(VGA_HS),
	.VGA_VS(VGA_VS),
	.VGA_DE(VGA_DE),
	.rotate_ccw(rotate_ccw),
	.no_rotate(no_rotate),
	.flip(1'b0),
	.video_rotated(video_rotated),
	.FB_EN(FB_EN),
	.FB_FORMAT(FB_FORMAT),
	.FB_WIDTH(FB_WIDTH),
	.FB_HEIGHT(FB_HEIGHT),
	.FB_BASE(FB_BASE),
	.FB_STRIDE(FB_STRIDE),
	.FB_VBL(FB_VBL),
	.FB_LL(FB_LL),
	.DDRAM_CLK(),
	.DDRAM_BUSY(1'b0),
	.DDRAM_BURSTCNT(),
	.DDRAM_ADDR(sr_addr),
	.DDRAM_DIN(sr_din),
	.DDRAM_BE(sr_be),
	.DDRAM_WE(sr_we),
	.DDRAM_RD()
);
assign FB_FORCE_BLANK = 1'b0;

assign LED_DISK = {1'b0, rom_loading};
reg [5:0] blink = '0;
always @(posedge clk_sys) if (frame_end) blink <= blink + 6'd1;
assign LED_USER = cpu_running ? blink[5] : 1'b1;

endmodule
