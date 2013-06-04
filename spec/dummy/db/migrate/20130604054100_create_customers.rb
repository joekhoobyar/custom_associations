class CreateCustomers < ActiveRecord::Migration
  def change
    create_table :customers do |t|
      t.string :first_name
      t.string :last_name
      t.string :customer_number
      t.date :deleted_at

      t.timestamps
    end
    create_table :customer_addresses do |t|
      t.integer :address_id
      t.string :customer_number
    end
  end
end
