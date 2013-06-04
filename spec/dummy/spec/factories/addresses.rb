# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :address do
    line1 "1234 Fake Street"
    city "Foobar"
    state "FL"
    zip "12345"
  end
end
