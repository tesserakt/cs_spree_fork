module Spree
  class CreditCard < Spree::Base
    belongs_to :payment_method
    has_many :payments, as: :source

    before_create :set_missing_info

    attr_accessor :number, :verification_value, :encrypted_data

    validates :month, :year, numericality: { only_integer: true }, if: :require_card_numbers?, on: :create
    validates :number, presence: true, if: :require_card_numbers?, on: :create
    validates :name, presence: true, if: :require_card_numbers?, on: :create
    validates :verification_value, presence: true, if: :require_card_numbers?, on: :create

    validate :expiry_not_in_the_past

    scope :with_payment_profile, -> { where('gateway_customer_profile_id IS NOT NULL') }

    # needed for some of the ActiveMerchant gateways (eg. SagePay)
    alias_attribute :brand, :cc_type

    CARD_TYPES = {
      visa: /^4[0-9]{12}(?:[0-9]{3})?$/,
      master: /(^5[1-5][0-9]{14}$)|(^6759[0-9]{2}([0-9]{10})$)|(^6759[0-9]{2}([0-9]{12})$)|(^6759[0-9]{2}([0-9]{13})$)/,
      diners_club: /^3(?:0[0-5]|[68][0-9])[0-9]{11}$/,
      american_express: /^3[47][0-9]{13}$/,
      discover: /^6(?:011|5[0-9]{2})[0-9]{12}$/,
      jcb: /^(?:2131|1800|35\d{3})\d{11}$/
    }

    def expiry=(expiry)
      return unless expiry.present?

      self[:month], self[:year] =
      if expiry.match(/\d\s?\/\s?\d/) # will match mm/yy and mm / yyyy
        expiry.delete(' ').split('/')
      elsif match = expiry.match(/(\d{2})(\d{2,4})/) # will match mmyy and mmyyyy
        [match[1], match[2]]
      end
      if self[:year]
        self[:year] = "20" + self[:year] if self[:year].length == 2
        self[:year] = self[:year].to_i
      end
      self[:month] = self[:month].to_i
    end

    def number=(num)
      @number = num.gsub(/[^0-9]/, '') rescue nil
    end

    # cc_type is set by jquery.payment, which helpfully provides different
    # types from Active Merchant. Converting them is necessary.
    def cc_type=(type)
      self[:cc_type] = case type
      when 'mastercard', 'maestro' then 'master'
      when 'amex' then 'american_express'
      when 'dinersclub' then 'diners_club'
      when '' then try_type_from_number
      else type
      end
    end

    def try_type_from_number
      numbers = number.delete(' ') if number
      CARD_TYPES.find{|type, pattern| return type.to_s if numbers =~ pattern}.to_s
    end

    def verification_value?
      verification_value.present?
    end

    # Show the card number, with all but last 4 numbers replace with "X". (XXXX-XXXX-XXXX-4338)
    def display_number
      "XXXX-XXXX-XXXX-#{last_digits}"
    end

    def actions
      %w{capture void credit}
    end

    # Indicates whether its possible to capture the payment
    def can_capture?(payment)
      payment.pending? || payment.checkout?
    end

    # Indicates whether its possible to void the payment.
    def can_void?(payment)
      !payment.void?
    end

    # Indicates whether its possible to credit the payment.  Note that most gateways require that the
    # payment be settled first which generally happens within 12-24 hours of the transaction.
    def can_credit?(payment)
      payment.completed? && payment.credit_allowed > 0
    end

    def has_payment_profile?
      gateway_customer_profile_id.present? || gateway_payment_profile_id.present?
    end

    # ActiveMerchant needs first_name/last_name because we pass it a Spree::CreditCard and it calls those methods on it.
    # Looking at the ActiveMerchant source code we should probably be calling #to_active_merchant before passing
    # the object to ActiveMerchant but this should do for now.
    def first_name
      name.to_s.split(/[[:space:]]/, 2)[0]
    end

    def last_name
      name.to_s.split(/[[:space:]]/, 2)[1]
    end

    def to_active_merchant
      ActiveMerchant::Billing::CreditCard.new(
        :number => number,
        :month => month,
        :year => year,
        :verification_value => verification_value,
        :first_name => first_name,
        :last_name => last_name,
      )
    end

    private

    def expiry_not_in_the_past
      if year.present? && month.present?
        if month.to_i < 1 || month.to_i > 12
          errors.add(:base, :expiry_invalid)
        else
          time = Time.zone.parse("#{year}-#{month}-1")
          if time < Time.zone.now.to_time.beginning_of_month
            errors.add(:base, :card_expired)
          end
        end
      end
    end

    def require_card_numbers?
      !self.encrypted_data.present? && !self.has_payment_profile?
    end

    def set_last_digits
      number.to_s.gsub!(/\s/,'')
      verification_value.to_s.gsub!(/\s/,'')
      self.last_digits ||= number.to_s.length <= 4 ? number : number.to_s.slice(-4..-1)
    end

    def set_missing_info
      set_last_digits
      if has_payment_profile?
        if matching_card = self.class.where(gateway_customer_profile_id: self.gateway_customer_profile_id, gateway_payment_profile_id: self.gateway_payment_profile_id).first
          self.cc_type     = matching_card.cc_type
          self.last_digits = matching_card.last_digits
          self.month       = matching_card.month
          self.name        = matching_card.name
          self.year        = matching_card.year
        end
      end
    end

  end
end
