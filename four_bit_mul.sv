module four_bit_mul(
    input clk,
    input [3:0] a,
    input [3:0] b,
    output [7:0] mul
    );
    
    
    reg [7:0] mul_temp;
    
    always@(posedge clk)begin
        mul_temp <= a * b;
    end
    
   assign mul = mul_temp; 
endmodule
