class NodeClass

  # All the field for the node object.
  attr_accessor :socket, :name, :ipAddress, :port, :sendBuffer, :recvBuffer,
                :distance, :nextHop, :isNeighbor, :linkCost, :lastUpdated

  # Only fields that are initialised upon creation of a new node object.
  def initialize()
    @sendBuffer = ""
    @recvBuffer = ""
	end

end