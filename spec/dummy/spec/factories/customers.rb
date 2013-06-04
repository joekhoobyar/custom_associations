# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :customer do
    first_name "John"
    last_name "Doe"
    customer_number "12345"
  end
end
