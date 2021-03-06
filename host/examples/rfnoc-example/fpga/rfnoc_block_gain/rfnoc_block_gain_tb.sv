//
// Copyright 2019 Ettus Research, A National Instruments Company
//
// SPDX-License-Identifier: LGPL-3.0-or-later
//
// Module: rfnoc_block_gain_tb
//
// Description: Testbench for the gain RFNoC block.
//

`default_nettype none


module rfnoc_block_gain_tb;

  `include "test_exec.svh"

  import PkgTestExec::*;
  import PkgChdrUtils::*;
  import PkgRfnocBlockCtrlBfm::*;
  import PkgRfnocItemUtils::*;

  //---------------------------------------------------------------------------
  // Testbench Configuration
  //---------------------------------------------------------------------------

  localparam [ 9:0] THIS_PORTID     = 10'h123;
  localparam [31:0] NOC_ID          = 32'h00000B16;
  localparam int    CHDR_W          = 64;
  localparam int    NUM_PORTS_I     = 1;
  localparam int    NUM_PORTS_O     = 1;
  localparam int    MTU             = 13;
  localparam int    SPP             = 64;
  localparam int    PKT_SIZE_BYTES  = SPP * 4; // Assumes 4 bytes per sample
  localparam int    STALL_PROB      = 25;      // Default BFM stall probability
  localparam real   CHDR_CLK_PER    = 5.0;     // 200 MHz
  localparam real   CTRL_CLK_PER    = 25.0;    // 40 MHz

  //---------------------------------------------------------------------------
  // Clocks and Resets
  //---------------------------------------------------------------------------

  bit rfnoc_chdr_clk;
  bit rfnoc_ctrl_clk;

  sim_clock_gen #(CHDR_CLK_PER) rfnoc_chdr_clk_gen (.clk(rfnoc_chdr_clk), .rst());
  sim_clock_gen #(CTRL_CLK_PER) rfnoc_ctrl_clk_gen (.clk(rfnoc_ctrl_clk), .rst());

  //---------------------------------------------------------------------------
  // Bus Functional Models
  //---------------------------------------------------------------------------

  // Backend Interface
  RfnocBackendIf backend (rfnoc_chdr_clk, rfnoc_ctrl_clk);

  // AXIS-Ctrl Interface
  AxiStreamIf #(32) m_ctrl (rfnoc_ctrl_clk, 1'b0);
  AxiStreamIf #(32) s_ctrl (rfnoc_ctrl_clk, 1'b0);

  // AXIS-CHDR Interfaces
  AxiStreamIf #(CHDR_W) m_chdr [NUM_PORTS_I] (rfnoc_chdr_clk, 1'b0);
  AxiStreamIf #(CHDR_W) s_chdr [NUM_PORTS_O] (rfnoc_chdr_clk, 1'b0);

  // Block Controller BFM
  RfnocBlockCtrlBfm #(.CHDR_W(CHDR_W)) blk_ctrl = new(backend, m_ctrl, s_ctrl);

  // Connect block controller to BFMs
  for (genvar i = 0; i < NUM_PORTS_I; i++) begin : gen_bfm_input_connections
    initial begin
      blk_ctrl.connect_master_data_port(i, m_chdr[i], PKT_SIZE_BYTES);
      blk_ctrl.set_master_stall_prob(i, STALL_PROB);
    end
  end
  for (genvar i = 0; i < NUM_PORTS_O; i++) begin : gen_bfm_output_connections
    initial begin
      blk_ctrl.connect_slave_data_port(i, s_chdr[i]);
      blk_ctrl.set_slave_stall_prob(i, STALL_PROB);
    end
  end

  //---------------------------------------------------------------------------
  // Device Under Test (DUT)
  //---------------------------------------------------------------------------

  // DUT Slave (Input) Port Signals
  logic [CHDR_W*NUM_PORTS_I-1:0] s_rfnoc_chdr_tdata;
  logic [       NUM_PORTS_I-1:0] s_rfnoc_chdr_tlast;
  logic [       NUM_PORTS_I-1:0] s_rfnoc_chdr_tvalid;
  logic [       NUM_PORTS_I-1:0] s_rfnoc_chdr_tready;

  // DUT Master (Output) Port Signals
  logic [CHDR_W*NUM_PORTS_O-1:0] m_rfnoc_chdr_tdata;
  logic [       NUM_PORTS_O-1:0] m_rfnoc_chdr_tlast;
  logic [       NUM_PORTS_O-1:0] m_rfnoc_chdr_tvalid;
  logic [       NUM_PORTS_O-1:0] m_rfnoc_chdr_tready;

  // Map the array of BFMs to a flat vector for the DUT connections
  for (genvar i = 0; i < NUM_PORTS_I; i++) begin : gen_dut_input_connections
    // Connect BFM master to DUT slave port
    assign s_rfnoc_chdr_tdata[CHDR_W*i+:CHDR_W] = m_chdr[i].tdata;
    assign s_rfnoc_chdr_tlast[i]                = m_chdr[i].tlast;
    assign s_rfnoc_chdr_tvalid[i]               = m_chdr[i].tvalid;
    assign m_chdr[i].tready                     = s_rfnoc_chdr_tready[i];
  end
  for (genvar i = 0; i < NUM_PORTS_O; i++) begin : gen_dut_output_connections
    // Connect BFM slave to DUT master port
    assign s_chdr[i].tdata        = m_rfnoc_chdr_tdata[CHDR_W*i+:CHDR_W];
    assign s_chdr[i].tlast        = m_rfnoc_chdr_tlast[i];
    assign s_chdr[i].tvalid       = m_rfnoc_chdr_tvalid[i];
    assign m_rfnoc_chdr_tready[i] = s_chdr[i].tready;
  end

  rfnoc_block_gain #(
    .THIS_PORTID         (THIS_PORTID),
    .CHDR_W              (CHDR_W),
    .MTU                 (MTU)
  ) dut (
    .rfnoc_chdr_clk      (rfnoc_chdr_clk),
    .rfnoc_ctrl_clk      (rfnoc_ctrl_clk),
    .rfnoc_core_config   (backend.cfg),
    .rfnoc_core_status   (backend.sts),
    .s_rfnoc_chdr_tdata  (s_rfnoc_chdr_tdata),
    .s_rfnoc_chdr_tlast  (s_rfnoc_chdr_tlast),
    .s_rfnoc_chdr_tvalid (s_rfnoc_chdr_tvalid),
    .s_rfnoc_chdr_tready (s_rfnoc_chdr_tready),
    .m_rfnoc_chdr_tdata  (m_rfnoc_chdr_tdata),
    .m_rfnoc_chdr_tlast  (m_rfnoc_chdr_tlast),
    .m_rfnoc_chdr_tvalid (m_rfnoc_chdr_tvalid),
    .m_rfnoc_chdr_tready (m_rfnoc_chdr_tready),
    .s_rfnoc_ctrl_tdata  (m_ctrl.tdata),
    .s_rfnoc_ctrl_tlast  (m_ctrl.tlast),
    .s_rfnoc_ctrl_tvalid (m_ctrl.tvalid),
    .s_rfnoc_ctrl_tready (m_ctrl.tready),
    .m_rfnoc_ctrl_tdata  (s_ctrl.tdata),
    .m_rfnoc_ctrl_tlast  (s_ctrl.tlast),
    .m_rfnoc_ctrl_tvalid (s_ctrl.tvalid),
    .m_rfnoc_ctrl_tready (s_ctrl.tready)
  );

  //---------------------------------------------------------------------------
  // Main Test Process
  //---------------------------------------------------------------------------

  // Multiply two signed 16-bit numbers and clip the result
  function shortint mult_and_clip(shortint a, shortint b);
    int      product;
    shortint result;
    product = int'(a) * int'(b);
    result = product[15:0];
    if (product > 16'sh7FFF) result = 16'sh7FFF;
    if (product < 16'sh8000) result = 16'sh8000;
    return result;
  endfunction : mult_and_clip

  // Generate a random signed 16-bit integer in the range [a, b]
  function shortint rand_shortint(int a, int b);
    return signed'($urandom_range(b - a)) + a;
  endfunction : rand_shortint

  localparam int REG_GAIN_ADDR = dut.REG_GAIN_ADDR;

  initial begin : tb_main

    // Initialize the test exec object for this testbench
    test.start_tb("rfnoc_block_gain_tb");

    // Start the BFMs running
    blk_ctrl.run();

    //--------------------------------
    // Reset
    //--------------------------------

    test.start_test("Flush block then reset it", 10us);
    blk_ctrl.flush_and_reset();
    test.end_test();

    //--------------------------------
    // Verify Block Info
    //--------------------------------

    test.start_test("Verify Block Info", 2us);
    `ASSERT_ERROR(blk_ctrl.get_noc_id() == NOC_ID, "Incorrect NOC_ID Value");
    `ASSERT_ERROR(blk_ctrl.get_num_data_i() == NUM_PORTS_I, "Incorrect NUM_DATA_I Value");
    `ASSERT_ERROR(blk_ctrl.get_num_data_o() == NUM_PORTS_O, "Incorrect NUM_DATA_O Value");
    `ASSERT_ERROR(blk_ctrl.get_mtu() == MTU, "Incorrect MTU Value");
    test.end_test();

    //--------------------------------
    // Test Sequences
    //--------------------------------

    begin
      // Read and write the gain register to make sure it updates correctly.
      logic [31:0] val32;
      test.start_test("Verify gain register", 5us);

      blk_ctrl.reg_read(REG_GAIN_ADDR, val32);
      `ASSERT_ERROR(
        val32 == 1, "Initial value for REG_GAIN_ADDR is not 1");

      // Write a value wider than the register to verify the width
      blk_ctrl.reg_write(REG_GAIN_ADDR, 32'h12348765);
      blk_ctrl.reg_read(REG_GAIN_ADDR, val32);
      `ASSERT_ERROR(
        val32 == 32'h8765, "Initial value for REG_GAIN_ADDR is not correct");
      
      test.end_test();
    end

    begin
      // Iterate through a series of gain values to test.
      localparam shortint MAX_TEST_VAL =  255;
      localparam shortint MIN_TEST_VAL = -255;
      static logic [15:0] test_gains[$] = { 
        1,     // Make sure unity gain leaves data unmodified
        -1,    // Make sure -1 negates data
        0,     // Make sure 0 gain results in 0
        37,    // Make sure a normal gain computes correctly
        -22,   // Make sure a normal gain computes correctly
        256    // Make sure a large gain causes clipping
        }; 

      foreach (test_gains[gain_index]) begin
        shortint     gain;
        int          num_bytes;
        chdr_word_t  send_payload[$];    // CHDR payload words (64-bit)
        chdr_word_t  recv_payload[$];    // CHDR payload words (64-bit)

        gain = test_gains[gain_index];

        test.start_test($sformatf("Test gain of %0d", int'(gain)), 10us);

        blk_ctrl.reg_write(REG_GAIN_ADDR, gain);

        // Generate a payload of random samples in the range [-255, 255], two
        // samples per CHDR word.
        send_payload = {};
        for (int i = 0; i < SPP/2; i++) begin
          send_payload.push_back({
            rand_shortint(MIN_TEST_VAL, MAX_TEST_VAL),  // 2nd sample I
            rand_shortint(MIN_TEST_VAL, MAX_TEST_VAL),  // 2nd sample Q
            rand_shortint(MIN_TEST_VAL, MAX_TEST_VAL),  // 1st sample I
            rand_shortint(MIN_TEST_VAL, MAX_TEST_VAL)   // 1st sample Q
          });
        end

        // Queue a packet for transfer
        blk_ctrl.send(0, send_payload);

        // Receive the output packet
        blk_ctrl.recv(0, recv_payload, num_bytes);

        // Check the resulting payload size
        `ASSERT_ERROR(num_bytes == SPP*4, 
          "Received payload didn't match size of payload sent");

        // Check the resulting payload data
        for (int i = 0; i < SPP/2; i++) begin
          chdr_word_t expected;
          chdr_word_t received;

          expected[63:48] = mult_and_clip(gain, send_payload[i][63:48]);
          expected[47:32] = mult_and_clip(gain, send_payload[i][47:32]);
          expected[31:16] = mult_and_clip(gain, send_payload[i][31:16]);
          expected[15: 0] = mult_and_clip(gain, send_payload[i][15: 0]);
          received = recv_payload[i];

          `ASSERT_ERROR(
            expected == received,
            $sformatf("For word %0d, gain %0d, input 0x%X, received 0x%X, expected 0x%X", 
                      i, gain, send_payload[i], recv_payload[i], expected));
        end

        test.end_test();
      end
    end

    //--------------------------------
    // Finish Up
    //--------------------------------

    // Display final statistics and results
    test.end_tb();
  end : tb_main

endmodule : rfnoc_block_gain_tb


`default_nettype wire
