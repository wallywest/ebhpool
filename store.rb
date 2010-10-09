module Ebhpool
module Store
	def self.run(pool)
	## TAKES AN INPUT HASH POOL THAT HAS KEYS OF CCLASSES AND VALUES OF AVAILABLE IPS. 
	## BREAKS DOWN THE HASH AND SETS UP LARGEST CONSECUTIVE IPS IN SORTED SETS USING REDIS
	## THE FOLLOWING KEYS ARE SETUP AND USED
	## KEYS | TYPE| DESCRIPTION
	## -------------------------------------
	## ipcount : string : total ips available
	## cclasses : set : lists all cclasses in pool
	## #{cclasses} : set : list all members for that variable cclass
	## ippool : sorted set : sorted set of cclass:id values ranked via their # of highest consecutive # list
	## #{cclasses}:id : set : all key id values in ippool sorted set
        ## #{cclasses}:ip:#{num} : list : list of all the actual available dclasses in that list

	@redis=Redis.new
	@redis.select "1"
	pool.each do |cclass,iparray|
		unless @redis.exists "#{cclass}" then setupcclass(cclass,iparray) end
        	iparray.each do |value|
    	            	@redis.sadd "temp","#{value}"
    	 	end
		## FIND WHICH IPS HAVE BEEN USED BUT NOT VIA HAB
        	@extractips=@redis.sdiff "#{cclass}", "temp"
		## FIND WHICH IPS HAVE BEEN GIVEN BACK TO THE POOL BUT NOT VIA HAB
        	@giveips=@redis.sdiff "temp", "#{cclass}"
        	@redis.del "temp"

        	if !@extractips.empty?
        	        ##PULL USED IPS OUT OF THE POOL AND REFACTOR SORT SETS/SETS/LISTS
			@redis.decrby "ipcount","#{@extractips.length}"
			@extractips.each {|x| @redis.srem "#{cclass}","#{x}"}
        	        extractips(cclass)
        	elsif !@giveips.empty?
			##ADD NEWLY FREED IPS INTO THE POOL AND REBUILD BASED ON NEW CCLASS SET
			@currentmem=@redis.smembers "#{cclass}"
			@redis.decrby "ipcount","#{@currentmem.length}"
			@giveips.each { |x| @redis.sadd "#{cclass}","#{x}"}
        	        mergeips(cclass)
        	end
	end
	end
	def self.setupcclass(cclass,iparray)
		##SETUP NEW CCLASS POOL 
                @redis.sadd "cclasses","#{cclass}"
                @g=[]
                @counter=@redis.incr "next.#{cclass}:ip"
                @redis.incrby "ipcount", "#{iparray.length}"
                iparray.each do |dclass|
                @redis.sadd "#{cclass}", "#{dclass}"
                @g << dclass.to_i
                        unless @g.length==1
                                if dclass.to_i-@g[-2] !=1
                                        @save=@g.pop
                                        @g.each {|x| @redis.lpush "#{cclass}:ip:#{@counter}", "#{x}"}
                                        @redis.zadd "ippool","#{@g.length}","#{cclass}:ip:#{@counter}"
                                        @redis.sadd "#{cclass}:ids", "#{cclass}:ip:#{@counter}"
                                        @counter=@redis.incr "next.#{cclass}:ip"

                                        @g=[]
                                        @g<<@save
                                end
                        end
                end
                @g.each {|x| @redis.lpush "#{cclass}:ip:#{@counter}", "#{x}"}
                @redis.zadd "ippool","#{@g.length}","#{cclass}:ip:#{@counter}"
                @redis.sadd "#{cclass}:ids", "#{cclass}:ip:#{@counter}"

	end
	def self.extractips(cclass)
        	@cclassset=@redis.smembers "#{cclass}:ids"
        	@cclassset.each do |set|
                	if (@redis.lrange "#{set}", "0", "-1").include?("#{@extractips.first}") then @lrange=set end
        	end
        	@iparray=@redis.lrange "#{@lrange}", "0","-1"
        	@offset= @extractips.last.to_i-@iparray.last.to_i+1
        	counter=@redis.incr "next.#{cclass}:ip"
        	@offset.times { @redis.rpoplpush "#{@lrange}","#{cclass}:ip:#{counter}"}
        	(@extractips.length).times { @redis.lpop "#{cclass}:ip:#{counter}" }
        	@newlrangelength=@redis.llen "#{cclass}:ip:#{counter}"
        	@lrangelength=@redis.llen "#{@lrange}"
        	@redis.sadd "#{cclass}:ids","#{cclass}:ip:#{counter}"
        	@redis.zadd "ippool", "#{@newlrangelength}","#{cclass}:ip:#{counter}"
       		@redis.zadd "ippool", "#{@lrangelength}","#{@lrange}"
	end
	def self.mergeips(cclass)
		(@redis.smembers "#{cclass}:ids").each do |x|
                	@redis.zrem "ippool","#{x}"
        	        @redis.del "#{x}"
        	end
		@redis.del "next.#{cclass}:ip"
        	@redis.del "#{cclass}:ids"
        	iparray=@redis.sort "#{cclass}"
		@redis.del "#{cclass}"
		setupcclass(cclass,iparray)
	end
end
end
