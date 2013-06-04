class Customer < ActiveRecord::Base
  
  has_one_custom :address, :conditions=>proc{ {:customer_number=>customer_number} }
    
end
