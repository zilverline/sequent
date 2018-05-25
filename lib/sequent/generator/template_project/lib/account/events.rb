class AccountAdded < Event
end

class AccountNameChanged < Event
  attrs name: String
end
