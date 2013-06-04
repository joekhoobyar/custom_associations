class Customer < ActiveRecord::Base
  
  has_one_custom :address,
    :joins=>['INNER JOIN customer_addresses ON customer_addresses.address_id = addresses.id'],
	  :conditions=>proc{ {:'customer_addresses.customer_number'=>(customer_number rescue Customer.arel_table[:customer_number])} }
    
end
