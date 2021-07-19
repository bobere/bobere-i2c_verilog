module i2c_shift(
	input clk,						//系统时钟
	input rst_n,					//复位信号
	input [5:0] cmd,				//读/写请求
	output reg trans_done,		//传输完成信号
	input [7:0] data_tx,			//要写入的数据
	input go,						//写数据开始
	inout i2c_sda,					//i2c数据线
	//inout wire sda,
	output reg i2c_sclk,			//i2c时钟线
	output reg ack_o,				//应答位
	output reg [7:0] data_rx	//接收数据
	);
	
	localparam scl_cnt=50_000_000/400_000;//时钟计算器，产生400khz频率
	reg i2c_sda_o;
	reg i2c_sda_oe;
	
	
	assign i2c_sda=i2c_sda_oe?(i2c_sda_o?1'bz:1'b0):1'bz;//i2c_sda信号产生
	//assign sda=i2c_sda_oe?(i2c_sda_o?1'bz:1'b0):1'bz;
	
	
	//分频400khz
	reg[19:0] div_cnt;
	reg div_cnt_en;
	always@(posedge clk or negedge rst_n)
	begin
		if(!rst_n) 
			div_cnt<=20'd0;
		else if(div_cnt_en)
			if(div_cnt==scl_cnt)
				div_cnt<=20'd0;
			else
				div_cnt<=div_cnt+1'b1;
		else
			div_cnt<=20'd0;
	end
	 
	wire sclk_plus;
	assign sclk_plus=div_cnt==scl_cnt;
	
	reg[3:0] state;
	localparam IDLE=4'd0,
				  GEN_STA=4'd1,
				  WR_DATA=4'd2,
				  RD_DATA=4'd3,
				  CHECK_ACK=4'd4,
				  GEN_ACK=4'd5,
				  GEN_STO=4'd6;
	
	reg [4:0] cnt;
	
	always@(posedge clk or negedge rst_n)
	begin
		if(!rst_n)
		begin
			data_rx<=0;
			i2c_sda_oe<=0;
			div_cnt_en<=0;
			i2c_sda_o<=0;
			trans_done<=0;
			ack_o<=0;
			state<=IDLE;
			cnt<=0;
		end
		else
		begin
			case(state)
			IDLE:
				begin
					trans_done<=1'b0;
					i2c_sda_oe<=1'h1;
					if(go)
					begin
						div_cnt_en<=1'b1;
						if(cmd==6'd0)//写数据请求，写数据之前产生起始位
							state<=GEN_STA;
						else if(cmd==6'd1)//读数据请求
							state<=RD_DATA;
						else
							state<=IDLE;
					end
					else 
					begin
						div_cnt_en<=1'b0;
						state<=IDLE;
					end
				end
				GEN_STA://产生起始位
				begin
					if(sclk_plus)
					begin
						if(cnt==3)
							cnt<=0;
						else
							cnt<=cnt+1'b1;
						case(cnt)
						0://此时sclk为低电平，拉高sda
							begin
								i2c_sda_oe<=1'b1;
								i2c_sda_o<=1'b1;
							end
						1: 
							begin
								i2c_sclk<=1'b1;//保持高电平
							end
						2:
							begin
								i2c_sclk<=1'b1;//拉低sda产生起始位
								i2c_sda_o<=1'b0;
							end
						3:
							begin
								i2c_sclk<=1'b0;//拉底sclk
							end
						endcase
						if(cnt==3)
						begin
							if(cmd==6'd0)//写数据请求
								state<=WR_DATA;
							else if(cmd==6'd1)//读数据请求
								state<=RD_DATA;
						end
					end
				end
			WR_DATA:
				begin
					if(sclk_plus)
					begin
						if(cnt==31)
							cnt<=0;
						else
							cnt<=cnt+1'b1;
						case(cnt)
//						0:i2c_sda_o<=data_tx[7-cnt[4:2]];i2c_sda_oe=1'b1;
//						1:i2c_sclk<=1;//拉高sclk
//						2:i2c_sclk<=1;//保持高
//						3:i2c_sclk<=0;//拉低
//						......
							0,4,8,12,16,20,24,28:
								begin
								i2c_sda_o<=data_tx[7-cnt[4:2]];//从上一个状态结束时sclk低电平，写入数据
									i2c_sda_oe=1'b1;
								end
							1,5,9,13,17,21,25,29:
								begin
									i2c_sclk<=1;//拉高sclk
								end
							2,6,10,14,18,22,26,30:
								begin
									i2c_sclk<=1;//保持高
								end
							3,7,11,15,19,23,27,31:
								begin
									i2c_sclk<=0;//拉低
								end
							default:
								begin
									i2c_sclk<=0;
									i2c_sda_o<=1;
								end
						endcase
						if(cnt==31)//写完检查应答位
							state<=CHECK_ACK;
					end
				end
			RD_DATA:
				begin
					if(sclk_plus)
					begin
						if(cnt==31)
							cnt<=0;
						else
							cnt<=cnt+1'b1;
						case(cnt)
							0,4,8,12,16,20,24,28:
								begin
									i2c_sda_oe<=0;
									i2c_sclk<=0;//拉低sclk,设置数据
								end
							1,5,9,13,17,21,25,29:
								begin
									i2c_sclk<=1;//拉高
								end
							2,6,10,14,18,22,26,30:
								begin
									i2c_sclk<=1;//保持高，并读数据
									data_rx<={data_rx[6:0],i2c_sda};
								end
							3,7,11,15,19,23,27,31:
								begin
									i2c_sclk<=0;//拉低
								end
							default:
								begin
									i2c_sclk<=1;
									i2c_sda_o<=1;
								end
						endcase
						if(cnt==31)
							state<=CHECK_ACK;
					end
				end
			CHECK_ACK://检查应答位
				begin
					if(sclk_plus)
					begin
						if(cnt==3)
							cnt<=0;
						else
							cnt<=cnt+1'b1;
						case(cnt)
							0:
								begin
									i2c_sda_oe<=0;
									i2c_sclk<=0;
								end
							1:
								begin
									i2c_sclk<=1;
								end
							2:
								begin
									i2c_sclk<=1;
									ack_o<=i2c_sda;
								end
							3:
								begin
									i2c_sclk<=0;
								end
							default:
								begin
									i2c_sclk<=0;
									i2c_sda_o<=1;
								end
						endcase
						if(cnt==3)
							if(cmd==6'd3)
								state<=GEN_STO;
							else 
							begin
								state<=IDLE;
								trans_done<=1'b1;
							end
					end
				end
			GEN_ACK://产生应答位
				begin
					if(sclk_plus)
					begin
						if(cnt==3)
							cnt<=0;
						else
							cnt<=cnt+1'b1;
						case(cnt)
							0:
								begin
									i2c_sda_oe<=1'b1;
									i2c_sclk=0;
									if(cmd==6'd5)
										i2c_sda_o<=1'b0;
									if(cmd==6'd6)
										i2c_sda_o<=1'b1;
								end
							1:
								begin
									i2c_sclk<=1;
								end
							2:
								begin
									i2c_sclk<=1;
								end
							3:
								begin
									i2c_sclk<=0;
								end
							default:
								begin
									i2c_sclk<=0;
									i2c_sda_o<=1;
								end
						endcase
						if(cnt==3)
							if(cmd==6'd3)
								state<=GEN_STO;
							else 
							begin
								state<=IDLE;
								trans_done<=1'b1;
							end
					end
				end
			GEN_STO:
			begin
				begin
					if(sclk_plus)
					begin
						if(cnt==3)
							cnt<=0;
						else
							cnt<=cnt+1'b1;
						case(cnt)
							0:
								begin
									i2c_sda_oe<=0;
									i2c_sclk<=0;
								end
							1:
								begin
									i2c_sda_oe<=1;
									i2c_sclk<=0;
								end
							2:
								begin
									i2c_sclk<=1;
								end
							3:
								begin
									i2c_sclk<=0;
								end
							default:
								begin
									i2c_sclk<=0;
									i2c_sda_o<=1;
								end
						endcase
						
					end
				end
			end
	
		endcase
		end
	end
	 
endmodule 