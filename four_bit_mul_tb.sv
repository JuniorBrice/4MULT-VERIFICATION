`timescale 1ns / 1ps
/*for this verification we will be testing 50 pseudo random input combinations for a 4 bit multiplier. 
   Such a testbench is unnecessary for a simple DUT like this one, but this was made more as an
   exercise and demonstration.
*/
//SIMPLE TRANSACTION CLASS --------------------------------------------------------------
class transaction;
    randc bit [3:0] a;
    randc bit [3:0] b;
    bit [7:0] mul;
      
    //display method to snoop on main transaction class if needed while buildingg/debugging testbench
    function void display();
        $display("[TRN] : a: %0d \t b: %0d \t mul: %0d \t at time %0t", a, b, mul,$time);
    endfunction

      //deep copy method which we will use to ensure proper randc cycling
      virtual function transaction copy();
        copy = new();
        copy.a = this.a;
        copy.b = this.b;
        copy.mul = this.mul;
      endfunction      
endclass

class error extends transaction; /*demonstration error injection class, where the corner case
                                    of a = 0 and b = 0 would be tested.*/
                                    
    // constraint a_b {a == 0; b == 0;}
    function transaction copy();
        copy = new();
        copy.a = 0;
        copy.b = 0;
        copy.mul = this.mul;
    endfunction
endclass

//SIMPLE INTERFACE ---------------------------------------------------------------------
interface four_bit_mul_if (input clk);
    logic [3:0] a;
    logic [3:0] b;
    logic [7:0] mul;
    
    //proper modport directions instantiated
    modport DUT (input clk, input a, input b, output mul);
    modport TB (output a, output b, input mul, input clk);  
endinterface

//SIMPLE MONITOR CLASS-------------------------------------------------------------------
class monitor;
    transaction trans;
    mailbox #(transaction) mbx;
    event next;
    virtual four_bit_mul_if mul_if;
    
    function new (mailbox #(transaction) mbx);
        this.mbx = mbx;
    endfunction
    
    task main;
        trans = new();
        forever begin
            repeat (2) @(posedge mul_if.clk);/*waiting for the clk x2, to synchronize our
                                                results in the console. we must wait 2 clock
                                                cycles since the multiplier takes 1 cycle to
                                                respond */
              trans.a  = mul_if.a;
              trans.b  = mul_if.b;
              trans.mul  = mul_if.mul;
              mbx.put(trans);
              $display ("[MON] : Data sent to Scoreboard.");
              //trans.display;
              -> next;
        end
    endtask
endclass

//SIMPLE SCOREBOARD CLASS-----------------------------------------------------------------
class scoreboard;
    transaction trans;
    mailbox #(transaction) mbx;
    event next;  //event from monitor signaling new values are sent, proceed with checking
    event gen_next; /*event sent to generator signal old values have been checked, proceed
                       witrh generation*/
    
    function new (mailbox #(transaction) mbx);
        this.mbx = mbx;
    endfunction  
    
    task main;
        trans = new();
        forever begin
            mbx.get(trans);
            $display("[SCO] : Received a: %0d, b: %0d, mul: %0d -- at time %0dns.", trans.a, trans.b, trans.mul, $time);
            //trans.display;
            compare(trans);
            $display("-----------------------------------------------------------------");
            -> gen_next;
            @(next);
        end
    endtask
    
    task compare (input transaction trans); //basic scorboard algorithm/checker model
         if(trans.mul == trans.a * trans.b) begin
            $display("[SCO] : RESULT MATCH");
         end else begin
            $error("[SCO] : UNEXPECTED RESULT, MISMATCH");  
         end
    endtask
endclass

//SIMPLE GENERATOR CLASS-----------------------------------------------------------------
class generator;
    transaction trans;
    mailbox #(transaction) mbx;
    event done; //event to aid in ending the simulation
    event drv_next; //event from driver signaling continue
    event sco_next; //event from scoreboard signaling continue
    
    function new (mailbox #(transaction) mbx);
        this.mbx = mbx;
        trans = new();
    endfunction
    
    task main;
        for (int i = 0; i < 50; i++)begin
            assert(trans.randomize) else $display("Randomization Failed at time %0t", $time);
                mbx.put(trans.copy); /*using a deep copy ensures proper randc cycling and 
                                        a separate object for each transaction,
                                        avoiding any timing/update issues. Also leaves
                                        room to inject errors/corner cases if need be*/
                $display("[GEN] : Data sent to Driver.");
                //trans.display; //snoop on transaction class
                @(drv_next); //waiting for the driver to finish with our values for this clock cycle.
                @(sco_next); //waiting for the sccoreboard to check values from previous clock cycle.     
       end
       -> done;
    endtask
endclass

//SIMPLE DRIVER CLASS--------------------------------------------------------------------
class driver;
    virtual four_bit_mul_if mul_if; /*interface declared outside of the driver hence virtual
                                       keyword. Will be connecting the interface in top tb*/
    transaction data;
    mailbox #(transaction) mbx;
    event next;  /*next event is used to allow the generator to proceed its task in 
                    synchrous logic. */
    function new (mailbox #(transaction) mbx);
        this.mbx = mbx;
    endfunction
    
    task main;
        forever begin /*driver will operate indefinitely since this is synchronous logic. 
                        simulation will exit using the done event when the generator has
                        finished its task*/
            repeat(2) @(posedge mul_if.clk); /*waiting for the clk x2, to synchronize our
                                                results in the console. There is a one clk
                                                cycle delay due to the synchronous logic. */
                mbx.get(data);
                mul_if.a <= data.a;
                mul_if.b <= data.b;
                $display("[DRV] : Received a: %0d, b: %0d -- at time %0dns.", data.a, data.b, $time); 
                -> next;               
        end  
    endtask
endclass

//Top level testbench module-----------------------------------------------------------------
module four_bit_mul_tb();

generator gen;
driver drv;
mailbox #(transaction) mbx;

monitor mon;
scoreboard sco;
mailbox #(transaction) mbx_two;

error err;
event done;

bit clk;
initial begin
    clk = 1;
end

always #10 clk = ~clk;

four_bit_mul_if mul_if(clk);

//four_bit_mul dut (mul_if.DUT);
four_bit_mul dut (.clk(mul_if.clk), .a(mul_if.a), .b(mul_if.b), .mul(mul_if.mul));

initial begin   
        mbx= new();
        gen = new(mbx);
        drv = new(mbx);
        
        err = new(); //constructing error inject class, though we will not be using it
        
        mbx_two = new();
        mon = new(mbx_two);
        sco = new(mbx_two);
        
        drv.mul_if = mul_if; //connecting driver to DUT
        mon.mul_if = mul_if; //connecting monitor to DUT
        done = gen.done; //connecting generator done event to top tb
        gen.drv_next = drv.next; //synchronizing gen and drv
        sco.next = mon.next; //synchronizing mon and sco
        gen.sco_next = sco.gen_next; /*synchronizing the generator and scoreboard. This
                                      was largely an asthetic choice, so the console could
                                      display clean cyclic values between all classes.*/
        //gen.trans = err;  // <-- error inject
end

//main fork/task
initial begin
    fork
        sco.main;
        gen.main;
        drv.main;
        mon.main;
    join_none
    
    wait(done.triggered);
      $finish;     
end 

//dumping waveform. ending simulation
initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
end
endmodule

/*A note: in the console, the simulation appears to have a clock period of 40ns, however this is not
the case. The clock period is 20ns, as you can see in tb top. We wait an extra clock period before 
generating our next values since the DUT takes a clock period to respond. We want our console
output to be nice and synchronized!*/
