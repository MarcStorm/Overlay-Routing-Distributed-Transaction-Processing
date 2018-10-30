require_relative 'priority_queue'

def setup(name1, cost1, name2, cost2, name3, cost3)
  pq = PriorityQueue.new
  pq.insert(name1, Integer(cost1))
  pq.insert(name2, Integer(cost2))
  pq.insert(name3, Integer(cost3))

  pq.printQueue
  puts "\n"

  STDOUT.puts(pq.extractMin)
  puts "\n"
  pq.printQueue
  puts "\n"
  #STDOUT.puts(pq.extractMin)
  STDOUT.puts(pq.elements.size)
  STDOUT.puts(pq.keys.size)

  pq.map.each { |k|
  STDOUT.puts(k)
  }
end

setup(ARGV[0], ARGV[1], ARGV[2], ARGV[3], ARGV[4], ARGV[5])
