module Ebhpool
def self.bestcase
     ##TAKES THE SORTED SET IPPOOL AND FINDS THE HIGHEST SCORE.  SORTED SET IS ORGANIZED BASE ON HIGHEST CONSECUTIVE AMOUNT OF IPS
     ##2 OPTIONS: ENOUGH IPS IN SAME CCLASS TO COVER REQUEST OR USE ANY AVAILBLE.
     @listids=@redis.zrange "ippool","0","-1"
     @cclass=@listids.last.sub(/:.*/,'')
     if (@redis.smembers "#{@cclass}").length >= @iprequestnum.to_i 
		##EXTRACT ONLY CCLASS RANGES IF TOTAL AMOUNT IS ENOUGH FOR REQUEST
		@listids.map {|x| if !x.match(/#{@cclass}/) then @listids.delete("#{x}") end}
     end
     ipchoice {|ips| yield ips }
end
def self.ipchoice
                idlist=[]
		left=@ipcount
		ip={}
		#TAKE FROM HIGHEST ZSCORE FIRST SHOULD NEVER REACH A ZERO STATE
                @listids.reverse.each do |id|
			cclass=id.sub(/:.*/,'')
			ip["#{cclass}"] ||= []
			idlist << "#{id}"
			maxidips=@redis.llen "#{id}"
			if maxidips < @ipcount then left=maxidips end
			left.times do
                        	iptoadd=@redis.rpop "#{id}"
                        	ip["#{cclass}"] << iptoadd
                        	@redis.srem "#{cclass}", "#{iptoadd}"
				@ipcount-=1
                	end
			##TIDY UP WHAT WE HAVE TAKEN
                	@redis.zadd "ippool", "#{maxidips-left}", "#{id}"
			if (@redis.zscore "ippool","#{id}").to_i==0
			    @redis.zrem "ippool","#{id}"
			    @redis.del "#{id}"
	                    @redis.srem "#{cclass}:ids", "#{id}"
                	end
			if @ipcount==0 then break end
                end
		yield ip
end
def self.gimme(iprequestnum)
	##STARTS A REDIS INSTANCE AND CHECKS FOR TOTAL IPS.  FORMATS THE IP REQUEST OUTPUT NEEDED FOR WHMCS"
	@redis=Redis.new
	@redis.select "1"
	@ipcount=iprequestnum
	@ip={"mainip"=>"","remainingips"=>""}
        if @ipcount > (@redis.get "ipcount").to_i then raise "not enough ips for request" end
        bestcase do |ips|
                ips.each_pair do |key,value|
                        value.collect {|x| "#{key}.#{x}"}.each do |x|
                                if @ip["mainip"].empty?
                                        @ip["mainip"]="#{x}"
                                else
                                        @ip["remainingips"] << "#{x}\s"
                                end
                        end
                        @ip["remainingips"].strip!
                end
        end
	##REDIS TOTAL IPCOUNT
	@redis.decrby "ipcount","#{iprequestnum}"	
	return @ip
end	
end
