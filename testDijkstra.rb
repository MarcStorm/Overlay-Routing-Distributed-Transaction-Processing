require_relative 'priority_queue'

def storeLinkStatePacket(packet)
  arr = packet.chomp().split(',')
  src = arr[0]
  seq = Integer(arr[1])
  destAndLinkCost = arr[2..-1] # Every destination is followed by the link cost from src to dest.

  # Check if the packet is a duplicate or old.
  if !$src_to_seq.has_key?(src) || seq > $src_to_seq[src]
    $src_to_seq[src] = seq
  end

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

end

def addToPriorityQueue()
  $edges.keys.each { |key|
    if key == "n1"
      $priorityQueue.insert(key, 0)
      $predecessor[key] = nil
      $distances[key] = 0
    else
      # Largest 32 bit number + 1. Assumed that all costs are represented by 32 bit integer.
      $priorityQueue.insert(key, 4611686018427387904)
      $predecessor[key] = nil
      $distances[key] = 4611686018427387904
    end
  }
end

def weight(u, v)
  return $edges[u][v]
end

def relax(u, v)
  #STDOUT.puts "relax method entered"
  #STDOUT.puts "Value of $distances[v] = #{$distances[v]}"
  #STDOUT.puts "Value of $distances[u] + weight(u,v) = #{$distances[u] + weight(u,v)}"
  if $distances[v] > $distances[u] + weight(u,v)
    #STDOUT.puts "if in relax method entered"
    $distances[v] = $distances[u] + weight(u,v)
    $priorityQueue.changeKey(v, $distances[v])
    STDOUT.puts "This is the value of v #{v} and the distance of v #{$distances[v]}."
    $predecessor[v] = u
  end
end

def dijkstra()
  # Add every node from the $edges hash to the priority queue with value infinity except from src which has value 0.
  $priorityQueue = PriorityQueue.new
  $predecessor = Hash.new
  $distances = Hash.new
  addToPriorityQueue()

  while !$priorityQueue.isEmpty
    STDOUT.puts($priorityQueue.inspect)
    u = $priorityQueue.extractMin
    $edges[u].keys.each { |v|
      relax(u, v)
    }
  end
end

def setup(args)
  $src_to_seq = Hash.new
  # Hash to store link state packets.
  $edges = Hash.new

  STDOUT.puts args
  STDOUT.puts "Start has been reached"

  storeLinkStatePacket("n1,1,n2,2")
  storeLinkStatePacket("n2,1,n1,2,n3,3,n4,7")
  storeLinkStatePacket("n3,1,n2,3,n4,2")
  storeLinkStatePacket("n4,1,n2,7,n3,2")


  dijkstra

  STDOUT.puts "End has been reached"
end

setup(ARGV[0])