# GROUP MEMBERS
# MARC STORM LARSEN, mlarsen
# SEBASTIAN PITUSCAN, pituscan

$port = nil
$hostname = nil

$nodeLock = Mutex.new

require 'socket'
require_relative 'node_class'
require_relative 'priority_queue'

# --------------------- Methods for flooding and routing. --------------------- #
# The methods include:
# - createLinkStatePacket
# - storeLinkStatePacket
# - reconstructLinkStatePacket
# - flooding
# - updateNodeObject
# - findNextHop
# - addToPriorityQueue
# - weight
# - relax
# - dijkstra

def createLinkStatePacket()
	# Construct the packet.
	# Packet should contain following information:
	# - "FLOODING"
	# - Source node name
	# - Sequence number
	# - Neighbor node name and link cost to the node.
	packet = ["FLOODING", $hostname, $sequenceNumber].join(',')
	$nodeLock.synchronize do
		$name_to_node.each_value { |n|
			if n.isNeighbor
				packet = [packet, n.name, n.linkCost].join(',')
			end
		}
	end

	# The sequence number has been used for a packet and therefore needs to be incremented for the next packet.
	$sequenceNumber += 1

	return packet
end

def storeLinkStatePacket(packet)
	src = packet[0]
	destAndLinkCost = packet[2..-1] # Every destination is followed by the link cost from src to dest.

	# Check if the inner hash has been initialised before.
	if !$edges.has_key?(src)
		$edges[src] = Hash.new
	end

	# Store destination and link cost information
	(0..destAndLinkCost.length-1).step(2) do |i|
		nodeName = destAndLinkCost[i]
		cost = Integer(destAndLinkCost[i+1])

		# We need to store information from the link state packet sent out by the node itself.
		$edges[src][nodeName] = cost
	end

	return
end

def reconstructLinkStatePacket(array)
	packet = ["FLOODING", array[0], array[1]].join(',')

	# The loop will increment by 2 the information in the array is stored as follows:
	# node name followed by the associated value.
	(2..array.length-1).step(2) do |i|
		packet = [packet, array[i], array[i+1]].join(',')
	end
	packet = [packet, ';'].join('')
	return packet
end

# THE PACKET IS NOT A STRING ANYMORE, IT'S AN ARRAY.
def flooding(packet)
	src = packet[0]
	seq = Integer(packet[1])

	# This commented code will prove that the packets are flooding in the network.
=begin
	if src == "n1" && $hostname != "n1"
		STDOUT.puts "PACKET FROM #{src} received."
	elsif src == "n2" && $hostname != "n2"
		STDOUT.puts "PACKET FROM #{src} received."
	elsif src == "n3" && $hostname != "n3"
		STDOUT.puts "PACKET FROM #{src} received."
	end
=end

	# Check if the packet is a duplicate or old.
	if !$src_to_seq.has_key?(src) || seq > $src_to_seq[src]
		$src_to_seq[src] = seq
	else
		return # Packet is old and shouldn't be processed.
	end

	storeLinkStatePacket(packet)

	$nodeLock.synchronize do
		# Flood to neighbors.
		# This for each might not need the first condition of the if statement.
		$socket_to_node.each { |socket, node|
			if node.isNeighbor && node.name != src # Send the packet to neighbors expect from the one you received it from.
				newPacket = reconstructLinkStatePacket(packet) # Pass packet, return a string.
				# Flood the packet. Depending on the content of the send buffer of the node the packets has to be added in
				# different ways.
				if $socket_to_node[socket].sendBuffer.size == 0
					$socket_to_node[socket].sendBuffer = newPacket
				else
					$socket_to_node[socket].sendBuffer = $socket_to_node[socket].sendBuffer.to_s + newPacket
				end
			end
		}
	end
end

def updateNodeObject(v)
	$nodeLock.synchronize do
		if $name_to_node.has_key?(v) # Check if the node object exists.
			node = $name_to_node[v]
			node.distance = $distances[v]
		else # If it doesn't exists, create a node object and add it to data structure.
			node = NodeClass.new
			node.socket = nil
			node.name = v
			node.ipAddress = nil
			node.port = $nodes[v]
			node.distance = $distances[v]
			node.nextHop = nil
			node.isNeighbor = false
			node.linkCost = nil
			$name_to_node[v] = node
		end
	end
end

def findNextHop()

	$edges.each_key { |k|

		# If k is equal to the $hostname there will be no nextHop to update in the 3 hash.
		if k == $hostname
			next
		end

		predecessor = $predecessor[k]

		# If the predecessor is the host itself, the nextHop should be set to k.
		if predecessor == $hostname
			$nodeLock.synchronize do
				node = $name_to_node[k]
				node.nextHop = k
			end
		else
			# If the predecessor is not the host itself, search recursively until the root of the tree (the host) has been
			# reached.
			currentNextHop = String.new
			while predecessor != $hostname
				# If the program doesn't seem to work try to include this STDOUT.puts statement.
				#STDOUT.puts "Program dysfuntional without this. See findNextHop()." # CAN'T GET THIS METHOD TO WORK WITHOUT THIS PRINT STATEMENT.
				currentNextHop = predecessor
				predecessor = $predecessor[currentNextHop]
			end

			$nodeLock.synchronize do
				node = $name_to_node[k]
				node.nextHop = currentNextHop
			end
		end
	}
end

# Add every node from the $edges hash to the priority queue with value infinity except
# from src which has value 0.
def addToPriorityQueue()
	$edges.keys.each { |key|
		if key == $hostname
			$priorityQueue.insert(key, 0)
			$predecessor[key] = nil
			$distances[key] = 0
		else
			# Largest 32 bit number + 1. Assumed that all costs are represented by 32 bit integer.
			$priorityQueue.insert(key, 1000000)
			$predecessor[key] = nil
			$distances[key] = 1000000
		end
	}
end

# Method will return the link cost between u and v.
def weight(u, v)
	return $edges[u][v]
end

# Method will relax two nodes, determining if the distance to a node should be updated.
def relax(u, v)
	if $distances[v] != nil && $distances[v] > $distances[u] + weight(u,v)
		$distances[v] = $distances[u] + weight(u,v)
		updateNodeObject(v) # Update the node object in 3 hash with the new distance from $hostname to v.
		$priorityQueue.changeKey(v, $distances[v])
		$predecessor[v] = u
		#STDOUT.puts "Predecessor of #{v} is set to #{u}, in datastructure #{$predecessor[v]}"
	end
end

def dijkstra()
	$priorityQueue = PriorityQueue.new
	$predecessor = Hash.new
	$distances = Hash.new
	addToPriorityQueue()

	while !$priorityQueue.isEmpty
		u = NodeClass.new
		$nodeLock.synchronize do
			u = $priorityQueue.extractMin
		end
		$edges[u].keys.each { |v|
			relax(u, v)
		}
	end

	findNextHop()
end

# Method that will add a node object to the three hashes.
# NOTE: this method can only be used when both socket, name and IP address of the node is known.
def addNode(node, socket, name, ipAddress)
	$nodeLock.synchronize do
		# Maybe we need to add a lock here.
		$socket_to_node[socket] = node
		$ip_to_node[ipAddress] = node
		$name_to_node[name] = node
	end
end

# --------------------- Part 0 --------------------- #
# Method to build an edge (connection) between two nodes in the network.
# This method is used when the EDGEB command is received from STDIN.
def edgeb(args)
	srcIP = args[0]
	destIP = args[1]
	dest = args[2]
	destPort = Integer
	$nodeLock.synchronize do
		destPort = $nodes[dest] # Get the port associated with the name.
	end

	socket = TCPSocket.new(destIP, destPort)

	# Create the node object and add additional information.
	node = NodeClass.new
	node.socket = socket
	node.name = dest
	node.ipAddress = destIP
	node.port = destPort
	node.distance = 1
	node.nextHop = dest
	node.isNeighbor = true
	node.linkCost = 1

	addNode(node, socket, dest, destIP) # Add the node object to the three hashes.

	$nodeLock.synchronize do
		# Send message to the node to build an edge (connection) with.
		# Message contains the necessary information in order for the receiving node to create a node object.
		if $socket_to_node[socket].sendBuffer.size == 0
			$socket_to_node[socket].sendBuffer = ["EDGEB", srcIP, $hostname, ';'].join(',')
		else
			$socket_to_node[socket].sendBuffer = $socket_to_node[socket].sendBuffer.to_s + ["EDGEB", srcIP, $hostname, ';'].join(',')
		end

	end
	return
end

# Method to build an edge (connection) between two nodes in the network.
# This method is used when the EDGEB command is received from another node in the network.
def edgeb_network(args, socket)
	destIP = args[0] # destIP is the IP address of the node who send the message.
	dest = args[1] # dest is the name of the node who send the message.
	destPort = Integer
	$nodeLock.synchronize do
		destPort = $nodes[dest] # Get the port associated with the name.
	end


	node = NodeClass.new
	$nodeLock.synchronize do
		node = $socket_to_node[socket]
		# Set parameters.
		node.name = dest
		node.ipAddress = destIP
		node.port = destPort
		node.distance = 1
		node.nextHop = dest
		node.isNeighbor = true
		node.linkCost = 1
	end

	$nodeLock.synchronize do
		# Add the node to the two remaining hashes. When the node object was created it was added to socket_to_node.
		$ip_to_node[destIP] = node
		$name_to_node[dest] = node
	end

	return
end

# Method that will write to node's current view of the routing table to a file.
def dumptable(args)
	filename = args[0]

	if !File.exists?(filename) then # If the file doesn't exists, create a new file.
		f = File.new(filename, "w")
	else # else if the file exists, open it and overwrite existing content.
		# "w" denotes that you can only write to the file and the existing content of the file will be overwritten.
		f = File.open(filename, "w")
	end

	$nodeLock.synchronize do
		# Go through one of the three hashes to extract the desired information and write it to the file.
		$name_to_node.each do |key, node|
			src = $hostname
			dst = key
			nextHop = node.nextHop
			distance = node.distance

			s = [src, dst, nextHop, distance.to_s].join(',')
			f.puts(s)
		end
	end
	f.close
end

# Method to cleanly shutdown a node.
def shutdown()
	$nodeLock.synchronize do
		# Close every socket connected to the node.
		$socket_to_node.keys.each { |s| s.close}
	end

	# Flush all pending write buffers (stdout, stderr).
	$stdout.flush
	$stderr.flush

	# Kill every thread.
	Thread.kill(@listeningThread)
	Thread.kill(@readWriteThread)
	Thread.kill(@timeThread)

	exit 0
end


# --------------------- Part 1 --------------------- # 
def edged(args)
	dest = args[0]

	$nodeLock.synchronize do
		# Probably need a lock here in case any other part of the code is using the object.
		node = $name_to_node[dest]
		node.socket.close	# Close the socket before deleting the object.

		$name_to_node.delete(dest)
	end
end

def edgeu(args)
	dest = args[0]
	cost = args[1]

	$nodeLock.synchronize do
		# Need a lock here as we are changing the object.
		node = $name_to_node[dest]

		if (node.isNeighbor)
			node.linkCost = cost
		end
	end
end

def getNeighbors()
	$nodeLock.synchronize do
		return $name_to_node.keys.sort
	end
end

def status()
	name = $hostname
	port = $port
	neighbors = getNeighbors().join(',')

	STDOUT.puts("Name: #{name} Port: #{port} Neighbors: #{neighbors}")
end

# --------------------- Part 2 --------------------- #

def createHeader(subHeader, headerSize)
	return [subHeader, headerSize.to_s].join(',')
end

def createSubHeader(msgType, src, dest, fragment_flag, fragOffset, lengthOfData, ttl, routingType, seq)
	return [msgType, src, dest, fragment_flag.to_s, fragOffset.to_s, lengthOfData.to_s, ttl.to_s, routingType, seq].join(',')
end

def getHeaderSize(subHeader)
	subHeaderSize = subHeader.bytesize
	headerSize = subHeaderSize + subHeaderSize.to_s.bytesize.to_i
	return headerSize
end

def getMessageSequenceNumber(dest)
	# Check if a message has been sent to dest before.
	if $messageSequenceNumber.has_key?(dest)
		# A message has been sent to dest before.
		seq = $messageSequenceNumber[dest]
		# Update sequence number
		$messageSequenceNumber[dest] += 1
	else
		# A message has not been sent to the destination before, so initialise the sequence number from 1.
		seq = 1
		$messageSequenceNumber[dest] = seq
	end

	# Return the sequence number
	return seq
end

def sendmsg(args)

	dest = args[0]

	#If the destination node isn't in the routing table for the source node the message can't be forwarded.
	# Print error.
	if !$name_to_node.has_key?(dest)
		STDOUT.puts "SENDMSG ERROR: HOST UNREACHABLE"
		return
	end

	seq = getMessageSequenceNumber(dest)

	msg = args[1..-1].join(' ') # Join by ' ' as they were split by ' ' in the handleThread.
	msgSize = msg.bytesize

	# Decide if the message should be fragmented or not.
	if msgSize > $maxPayload
		counter = 0
		while (counter < msgSize)
			# Prepare msg to be send by creating a header.
			subHeader = createSubHeader("SENDMSG", $hostname, dest, 1, counter, msgSize, 20, nil, seq)
			headerSize = getHeaderSize(subHeader)
			header = createHeader(subHeader, headerSize)
			# Fragment message.
			subMsg = msg.slice(counter..(counter+$maxPayload-1))
			# Add SENDMSG type and header to message fragment.
			p = [header, subMsg].join(':') # The first ':' read will denote the end of the header.
			packet = [p, ';'].join('')
			# Add fragment to the send buffer
			$nodeLock.synchronize do
				nextHopNode = $name_to_node[$name_to_node[dest].nextHop]
				if nextHopNode.sendBuffer.size == 0
					nextHopNode.sendBuffer = packet
				else
					nextHopNode.sendBuffer = nextHopNode.sendBuffer.to_s + packet
				end
			end

			$nodeLock.synchronize do
				counter += $maxPayload
			end
		end
	else
		# Message doesn't need to be fragmented.
		# Prepare msg to be send by creating a header.
		subHeader = createSubHeader("SENDMSG", $hostname, dest, 0, 0, msgSize, 20, nil, seq)
		headerSize = getHeaderSize(subHeader)
		header = createHeader(subHeader, headerSize)
		p = [header, msg].join(":") # The first ':' read will denote the end of the header.
		packet = [p, ';'].join('')
		# Add the fragment to the nextHob to the destination node. Even if the destination node is a neighbor, the nextHop
		# will still make sure the packet reach the destination.
		$nodeLock.synchronize do
			nextHopNode = $name_to_node[$name_to_node[dest].nextHop]
			if nextHopNode.sendBuffer.size == 0
				nextHopNode.sendBuffer = packet
			else
				nextHopNode.sendBuffer = nextHopNode.sendBuffer.to_s + packet
			end
		end
	end
end

# header is an array, msg is a string.
def sendmsg_network(header, msg)
	# Header contains 9 fields. The first field was removed by the handler, which leaves 8 fields.

	# Check if the message has reached the final destination.
	dest = header[1]
	if dest == $hostname
		# Packet has reached final destination.
		# Determine if the packet is a fragmentation or not.
		fragmented = header[2]
		if fragmented.eql?("1")
			# Packet is fragmented. Store the fragment and check if the entire message has been received.
			# Reconstruct message.
			src = header[0]
			fragmentOffset = header[3]
			msgSize = header[4].to_i
			seq = header[7]

			$nodeLock.synchronize do
				# key = src of message, value = hash. Key = sequence of the current message being stored, Value = message fragment.
				if !$messageBuffer.has_key?(src)
					# Since a message hasn't been received from that source before there's no need to check the sequence number.
					$messageBuffer[src] = Hash.new
				end
			end

			$nodeLock.synchronize do
				if !$messageBuffer[src].keys.empty?
					$messageBuffer[src].each_key { |k|
						if k.to_i > seq.to_i
							# If this state is reached, it means that the message fragment is old and shouldn't be stored.
							return
						end
					}
				end
			end

			$nodeLock.synchronize do
				if !$messageBuffer[src].has_key?(seq)
					$messageBuffer[src][seq] = Hash.new
				end
			end

			$nodeLock.synchronize do
				if !$messageBuffer[src][seq].has_key?(fragmentOffset)
					$messageBuffer[src][seq][fragmentOffset] = msg
				end
			end

			numberOfFragmentOffsets = 0

			$nodeLock.synchronize do
				$messageBuffer[src][seq].each_key { |f|
					numberOfFragmentOffsets += 1
				}
			end

			completeMsg = String
			$nodeLock.synchronize do
				if numberOfFragmentOffsets == (msgSize / $maxPayload.to_f).ceil
					# The message is complete and ready to be printed.
					$messageBuffer[src][seq].each_value { |subMsg|
						completeMsg = completeMsg + subMsg.chomp
					}
					STDOUT.puts "SENDMSG: #{src} -- > #{completeMsg}"
				end
			end
		else
			# Packet is not fragmented.
			src = header[0]
			STDOUT.puts "SENDMSG: #{src} -- > #{msg.chomp}"
		end
	else
		# Message has not reached the final destination.

		# Check if the packet is too old to keep on sending.
		ttl = header[5].to_i
		if ttl <= 0
			# Possibly send back an error to src.
			return
		else
			ttl -= 1
		end

		# Replace time to live (ttl) value in array.
		header[5] = ttl.to_s
		# Construct new header and packet.
		newHeader = createSubHeader("SENDMSG", header[0], header[1], header[2], header[3], header[4], header[5], header[6], header[7])
		headerSize = getHeaderSize(newHeader)
		header = createHeader(newHeader, headerSize)
		p = [header, msg].join(":") # The first ':' read will denote the end of the header.
		packet = [p, ';'].join('')

		# Forward the packet to the nextHob of the final destination node.
		$nodeLock.synchronize do
			nextHopNode = $name_to_node[$name_to_node[dest].nextHop]
			if nextHopNode.sendBuffer.size == 0
				nextHopNode.sendBuffer = packet
			else
				nextHopNode.sendBuffer = nextHopNode.sendBuffer.to_s + packet
			end
		end
	end
end

def ping(args)
	dest = args[0]
	numpings = args[1].to_i
	delay = args[2]
	node = $name_to_node[dest]
	for i in 1..numpings
		sleep(1)
		#sendmsg(["n2","--PING\n"])


		if !$name_to_node.has_key?(dest)
			STDOUT.puts "PING ERROR: HOST UNREACHABLE"
			return
		end

		seq = 0
		time = 0

		header = ["PING", numpings, delay].join(",")
		packet = [header, [seq, dest, time]].join(":") # The first ':' read will denote the end of the header.


		$nodeLock.synchronize do
			nextHopNode = $name_to_node[$name_to_node[dest].nextHop]
			nextHopNode.sendBuffer = nextHopNode.sendBuffer.to_s + packet
		end
	end
end

def ping_network(header, msg)
	# Header contains 9 fields. The first field was removed by the handler, which leaves 8 fields.

	# Check if the message has reached the final destination.
	dest = header[1]
	if dest == $hostname
		# Packet has reached final destination.

		src = header[0]
		STDOUT.puts "PING: #{src} -- > #{msg.chomp}"

	else

		seq = 0
		time = 0

		header = ["PING", numpings, delay].join(",")
		packet = [header, [seq, dest, time]].join(":") # The first ':' read will denote the end of the header.


		$nodeLock.synchronize do
			nextHopNode = $name_to_node[$name_to_node[dest].nextHop]
			nextHopNode.sendBuffer = nextHopNode.sendBuffer.to_s + packet
		end
	end
end

def traceroute(args)
	STDOUT.puts "TRACEROUTE: not implemented"
end

def ftp(args)
	STDOUT.puts "FTP: not implemented"
end

# --------------------- Part 3 --------------------- # 
def circuit(args)
	STDOUT.puts "CIRCUIT: not implemented"
end

def handleThread()
	while(line = STDIN.gets)
		line = line.strip
		arr = line.split(' ')
		cmd = arr[0]
		args = arr[1..-1]
		case cmd
		when "EDGEB"; edgeb(args)
		when "EDGED"; edged(args)
		when "EDGEU"; edgeu(args)
		when "DUMPTABLE"; dumptable(args)
		when "SHUTDOWN"; shutdown
		when "STATUS"; status
		when "SENDMSG"; sendmsg(args)
		when "SENDMSGACK"; sendmsgack(args)
		when "PING"; ping(args)
		when "TRACEROUTE"; traceroute(args)
		when "FTP"; ftp(args)
		when "CIRCUIT"; circuit(args)
		else STDOUT.puts "ERROR: INVALID COMMAND \"#{cmd}\""
		end
	end
end

def handleNetwork(recvBuffer, socket)
	#STDOUT.puts recvBuffer.inspect
	arr = recvBuffer.chomp.split(':')
	#STDOUT.puts arr.inspect
	# This assumes that only functions using a header are called with a header.
	if arr.size > 1
		# The recvBuffer contains a header.
		header = arr[0].split(',')
		cmd = header[0]
		subHeader = header[1..-1]
		msg = arr[1..-1].join(':') # If the message contained any ':', place them in the message again.
	else
		arr = recvBuffer.chomp().split(',')
		cmd = arr[0]
		args = arr[1..-1]
	end

	case cmd
		when "EDGEB"; edgeb_network(args, socket)
		when "SENDMSG"; sendmsg_network(subHeader, msg)
		when "PING"; ping_network(subheader, msg)
		when "TRACEROUTE"; traceroute_network(args)
		when "FTP"; ftp_network(args)
		when "CIRCUIT"; circuit_network(args)
		when "FLOODING"; flooding(args)
	end
	return
end

def readWriteThread
	# Use this thread for flooding and dijkstra's algorithm.
	# For flooding:
	# - Having internal clock.
	# - When updateInterval have passed it's okay for the thread to flood.
	# - Flooding on the precise time of updateInterval is not necessary.

	timeout = 0.25

	loop {

		if (($time - $timeLastUpdate) >= $updateInterval)
			#STDOUT.puts "IF entered."
			$nodeLock.synchronize do
				$timeLastUpdate = $time
			end

			# Create link state packet for the node itself.
			packet = createLinkStatePacket

			# Pass packet to own flooding method to start constructing the graph and to flood to neighbors.
			handleNetwork(packet, nil)

			# The packet has been flooding to the network.
			# Get an overview of the network by running dijkstra's.
			dijkstra
		end

		rTemp = Array.new
		$nodeLock.synchronize {
			rTemp = $socket_to_node.keys
		}

		r,w,e = IO.select(rTemp, nil, nil, timeout)

		# Check that the array isn't empty.
		if(r != nil)
			r.each { |readable_socket|
				$nodeLock.synchronize do
					$socket_to_node[readable_socket].recvBuffer = readable_socket.gets()
					#STDOUT.puts $socket_to_node[readable_socket].recvBuffer.chomp.inspect
				end
			}

			r.each { |readable_socket|
				buffer = String.new
				$nodeLock.synchronize do
					buffer = $socket_to_node[readable_socket].recvBuffer
				end
				handleNetwork(buffer, readable_socket)
			}
		end

		# If there's something to send to the other nodes, send it.
		$nodeLock.synchronize do
			$socket_to_node.values.each {|n|
				# The order of the conditions is important. If the length of a string i
				while n.sendBuffer != nil && n.sendBuffer.length > 0
					arr = n.sendBuffer.split(';')
					nextPacket = arr[0]
					#STDOUT.puts nextPacket.inspect
					if arr.size > 1 # If true, then there's more commands in the send buffer and should be send seperately.
						n.sendBuffer = arr[1..-1].join(';')
						n.socket.puts(nextPacket)
					else
						n.socket.puts(nextPacket)
						n.sendBuffer = arr[1..-1]
					end
				end
			}
		end
	}
end

def listeningThread
	server = TCPServer.new($port)

	loop {
		client = server.accept()
		node = NodeClass.new
		node.socket = client
		$nodeLock.synchronize do
			$socket_to_node[client] = node # add node to hash
		end
	}
end

def timeThread
	timeUpdateInterval = 0.1

	loop {
		sleep(timeUpdateInterval)
		# Might need to add a lock here as we are changing a global variable.
		$nodeLock.synchronize do
			$time += timeUpdateInterval
		end
	}
end

# Method to parse the information given in nodes.txt to an global Hash.
def parseNodes(nodes)
  fHandle = File.open(nodes)
  while(line = fHandle.gets)
    arr = line.chomp.split(',')

    node_name = arr[0]
    node_port = Integer(arr[1])

    $nodes[node_name] = node_port
  end
end

# Method to parse the information given in config to an global Hash.
def parseConfig(config)
	fHandle = File.open(config)
	while(line = fHandle.gets)
		arr = line.chomp.split('=')

		option = arr[0]
		value = Integer(arr[1])

		$config[option] = value
	end
end

def setup(hostname, port, nodes, config) #Example: n1 10241 nodes config

	$time = Time.new

	$hostname = hostname
	$port = Integer(port) # Parse the string port to an integer.

	# Hashes to store information from the nodes.txt and config file.
	$nodes = Hash.new
	$config = Hash.new

	# The header length needs to be variable and not static.
	#$headerLength = 100

	# Parse information in given files to internal data structures.
	parseNodes(nodes)
	parseConfig(config)

	# Three hashes that allows to get access to the same node object in three different ways.
	$socket_to_node = Hash.new
	$ip_to_node = Hash.new
	$name_to_node = Hash.new

	$updateInterval = $config["updateInterval"]
	$maxPayload = $config["maxPayload"]
	$pingTimeout = $config["pingTimeout"]

	# Sequence variable used for the link state packets.
	$sequenceNumber = 1
	# Hash to keep track for link packets received from other nodes.
	$src_to_seq = Hash.new
	# Hash to store link state packets.
	$edges = Hash.new

	# ListeningThread is used for listening for incoming connections from other nodes in the network.
	# ReadWriteThread is used for reading what is available on readable sockets and to write what's stored in write buffers.
	# HandleThread is used for handling instructions from STDin (Terminal).
	@listeningThread = Thread.new{listeningThread}
	@readWriteThread = Thread.new{readWriteThread}
	@handleThread = Thread.new{handleThread}
	$time = Time.now
	$timeLastUpdate = $time
	@timeThread = Thread.new{timeThread}

	# Hash to store the fragments of a message.
	$messageBuffer = Hash.new # key = src of message, value = hash. Key = sequence of the current message being stored, Value = message fragment.
	# Hash to store sequence number for messages for each node.
	$messageSequenceNumber = Hash.new
	# Time object used to determine if the packet fragments was lost in the network.
	$lastFragmentReceived = $time

	@listeningThread.join
	@readWriteThread.join
	@handleThread.join
end

setup(ARGV[0], ARGV[1], ARGV[2], ARGV[3])