class PriorityQueue

  attr_accessor :map, :keys, :elements

  def initialize
    @elements = []
    @keys = []
    @map = Hash.new
  end

  def parent(node)
    return (node - 1) / 2
  end

  def left(node)
    return node * 2 + 1
  end

  def right(node)
    return node * 2 + 2
  end

  def swap(src, trgt)
    @elements[src], @elements[trgt] = @elements[trgt], @elements[src]
    @keys[src], @keys[trgt] = @keys[trgt], @keys[src]

    @map[@elements[src]] = src
    @map[@elements[trgt]] = trgt
  end

  def bubbleUp(node)
    while node > 0 && @keys[node] < @keys[parent(node)]
      swap(parent(node), node)
    end
  end

  def bubbleDown(node)
    while left(node) < @keys.size
      if right(node) >= @keys.size || @keys[left(node)] < @keys[right(node)]
        min = left(node)
      else
        min = right(node)
      end

      if @keys[node] > @keys[min]
        swap(node, min)
        node = min
      else
        break
      end
    end
  end

=begin
  def printQueue
    @elements.each { |x| puts x }
    @keys.each { |x| puts x }
  end
=end

  def isEmpty
    return @keys.size == 0
  end

  def changeKey(element, newKey)
    if @map.has_key?(element)
      index = @map[element]
      @keys[index] = newKey
      bubbleUp(index)
      bubbleDown(index)
    end
  end

  def extractMin
    if @elements.size == 0
    end

    min = @elements[0]

    swap(0, @keys.size - 1)

    @keys.pop
    @elements.pop

    bubbleDown(0)

    @map.delete(min)

    return min
  end

  def insert(element, key)
    if !@elements.include?(element)
      @elements << element
      @keys << key
      @map[element] = (@elements.size - 1)

      bubbleUp(@keys.size - 1)
    end
  end

  private :swap, :right, :left, :parent, :bubbleDown, :bubbleUp

end