require 'support/cattr_accessor'
require 'money/bank/no_exchange_bank'
require 'money/bank/variable_exchange_bank'
require 'money/core_extensions'

# === Usage with ActiveRecord
# 
# Use the compose_of helper to let active record deal with embedding the money
# object in your models. The following example requires a cents and a currency field.
# 
#   class ProductUnit < ActiveRecord::Base
#     belongs_to :product
#     composed_of :price, :class_name => "Money", :mapping => [ %w(cents cents), %w(currency currency) ]
# 
#     private        
#       validate :cents_not_zero
#     
#       def cents_not_zero
#         errors.add("cents", "cannot be zero or less") unless cents > 0
#       end
#     
#       validates_presence_of :sku, :currency
#       validates_uniqueness_of :sku        
#   end
#   
class Money
  include Comparable

  attr_reader :cents, :currency, :precision

  class MoneyError < StandardError# :nodoc:
  end

  # Bank lets you exchange the object which is responsible for currency
  # exchange. 
  # The default implementation just throws an exception. However money
  # ships with a variable exchange bank implementation which supports
  # custom excahnge rates:
  #
  #  Money.bank = VariableExchangeBank.new
  #  Money.bank.add_rate("USD", "CAD", 1.24515)
  #  Money.bank.add_rate("CAD", "USD", 0.803115)
  #  Money.us_dollar(100).exchange_to("CAD") => Money.ca_dollar(124)
  #  Money.ca_dollar(100).exchange_to("USD") => Money.us_dollar(80)
  @@bank = NoExchangeBank.new
  cattr_accessor :bank

  @@default_currency = "USD"
  cattr_accessor :default_currency
  
  # String to use when formating zero values
  cattr_accessor :zero

  # Creates a new money object. 
  #  Money.new(100) 
  # 
  # Alternativly you can use the convinience methods like 
  # Money.ca_dollar and Money.us_dollar 
  def initialize(cents, currency = default_currency, precision = 2)
    @cents, @currency, @precision = cents.round, currency, precision
  end

  # Do two money objects equal? Only works if both objects are of the same currency
  def eql?(other_money)
    cents == other_money.cents && currency == other_money.currency
  end

  def <=>(other_money)
    if currency == other_money.currency
      cents <=> other_money.cents
    else
      cents <=> other_money.exchange_to(currency).cents
    end
  end

  def +(other_money)
    other_money = other_money.exchange_to(currency) unless other_money.currency == currency
    
    new_precision = [precision, other_money.precision].max
    Money.new(to_precision(new_precision).cents + other_money.to_precision(new_precision).cents, currency, new_precision)
  end

  def -(other_money)
    other_money = other_money.exchange_to(currency) unless other_money.currency == currency
    
    new_precision = [precision, other_money.precision].max
    Money.new(to_precision(new_precision).cents - other_money.to_precision(new_precision).cents, currency, new_precision)
  end

  def -@
    Money.new(-cents, currency, precision)
  end

  # multiply money by fixnum
  def *(fixnum)
    Money.new(cents * fixnum, currency, precision)
  end

  # divide money by fixnum
  def /(fixnum)
    Money.new(cents / fixnum, currency, precision)
  end
  
  # Test if the money amount is zero
  def zero?
    cents == 0 
  end


  # Format the price according to several rules
  # Currently supported are :with_currency, :no_cents and :html
  #
  # with_currency: 
  #
  #  Money.ca_dollar(0).format => "free"
  #  Money.ca_dollar(100).format => "$1.00"
  #  Money.ca_dollar(100).format(:with_currency) => "$1.00 CAD"
  #  Money.us_dollar(85).format(:with_currency) => "$0.85 USD"
  #
  # no_cents:  
  #
  #  Money.ca_dollar(100).format(:no_cents) => "$1"
  #  Money.ca_dollar(599).format(:no_cents) => "$5"
  #  
  #  Money.ca_dollar(570).format(:no_cents, :with_currency) => "$5 CAD"
  #  Money.ca_dollar(39000).format(:no_cents) => "$390"
  #
  # html:
  #
  #  Money.ca_dollar(570).format(:html, :with_currency) =>  "$5.70 <span class=\"currency\">CAD</span>"
  def format(*rules)
    return self.class.zero if zero? && self.class.zero
    
    rules = rules.flatten

    formatted = "$" + to_s(rules.include?(:no_cents) ? 0 : 2)

    if rules.include?(:with_currency)
      formatted << " "
      formatted << '<span class="currency">' if rules.include?(:html)
      formatted << currency
      formatted << '</span>' if rules.include?(:html)
    end
    formatted
  end

  # Money.ca_dollar(100).to_s => "1.00"
  def to_s(show_precision = precision)
    if show_precision > 0
      sprintf("%.#{show_precision}f", to_f  )
    else
      sprintf("%d", cents.to_f / 10 ** (precision - show_precision)  )
    end
  end
  
  def to_f
    cents.to_f / 10 ** precision
  end

  # Recieve the amount of this money object in another currency   
  def exchange_to(other_currency)
    self.class.bank.exchange(self, other_currency)
  end
  
  def to_precision(new_precision)
    difference = new_precision - precision
    new_cents = difference > 0 ? cents * 10**difference : (cents.to_f / 10**difference.abs).round
    Money.new(new_cents, currency, new_precision)
  end

  # Create a new money object with value 0
  def self.empty(currency = default_currency)
    Money.new(0, currency)
  end

  # Create a new money object using the Canadian dollar currency
  def self.ca_dollar(num)
    Money.new(num, "CAD")
  end

  # Create a new money object using the American dollar currency
  def self.us_dollar(num)
    Money.new(num, "USD")
  end

  # Create a new money object using the Euro currency
  def self.euro(num)
    Money.new(num, "EUR")
  end

  # Recieve a money object with the same amount as the current Money object
  # in american dollar 
  def as_us_dollar
    exchange_to("USD")
  end

  # Recieve a money object with the same amount as the current Money object
  # in canadian dollar 
  def as_ca_dollar
    exchange_to("CAD")
  end

  # Recieve a money object with the same amount as the current Money object
  # in euro
  def as_ca_euro
    exchange_to("EUR")
  end  

  # Conversation to self
  def to_money
    self
  end  
end