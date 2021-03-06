# -*- coding: utf-8 -*-
mydir = File.expand_path(File.dirname(__FILE__))

begin
  require 'psych'
rescue LoadError
end

require 'i18n'
require 'set' # Fixes a bug in i18n 0.6.11

if I18n.respond_to?(:enforce_available_locales=)
  I18n.enforce_available_locales = true
end
I18n.load_path += Dir[File.join(mydir, 'locales', '*.yml')]


module Faker
  class Config
    @locale = nil

    class << self
      attr_writer :locale
      def locale
        @locale || I18n.locale
      end

      def own_locale
        @locale
      end

    end
  end

  class Base
    Numbers = Array(0..9)
    ULetters = Array('A'..'Z')
    Letters = ULetters + Array('a'..'z')

    class << self
      ## make sure numerify results doesn’t start with a zero
      def numerify(number_string)
        number_string.sub(/#/) { (rand(9)+1).to_s }.gsub(/#/) { rand(10).to_s }
      end

      def letterify(letter_string)
        letter_string.gsub(/\?/) { ULetters.sample }
      end

      def bothify(string)
        letterify(numerify(string))
      end

      # Given a regular expression, attempt to generate a string
      # that would match it.  This is a rather simple implementation,
      # so don't be shocked if it blows up on you in a spectacular fashion.
      #
      # It does not handle ., *, unbounded ranges such as {1,},
      # extensions such as (?=), character classes, some abbreviations
      # for character classes, and nested parentheses.
      #
      # I told you it was simple. :) It's also probably dog-slow,
      # so you shouldn't use it.
      #
      # It will take a regex like this:
      #
      # /^[A-PR-UWYZ0-9][A-HK-Y0-9][AEHMNPRTVXY0-9]?[ABEHMNPRVWXY0-9]? {1,2}[0-9][ABD-HJLN-UW-Z]{2}$/
      #
      # and generate a string like this:
      #
      # "U3V  3TP"
      #
      def regexify(re)
        re = re.source if re.respond_to?(:source) # Handle either a Regexp or a String that looks like a Regexp
        re.
          gsub(/^\/?\^?/, '').gsub(/\$?\/?$/, '').                                                                      # Ditch the anchors
          gsub(/\{(\d+)\}/, '{\1,\1}').gsub(/\?/, '{0,1}').                                                             # All {2} become {2,2} and ? become {0,1}
          gsub(/(\[[^\]]+\])\{(\d+),(\d+)\}/) {|match| $1 * Array(Range.new($2.to_i, $3.to_i)).sample }.                # [12]{1,2} becomes [12] or [12][12]
          gsub(/(\([^\)]+\))\{(\d+),(\d+)\}/) {|match| $1 * Array(Range.new($2.to_i, $3.to_i)).sample }.                # (12|34){1,2} becomes (12|34) or (12|34)(12|34)
          gsub(/(\\?.)\{(\d+),(\d+)\}/) {|match| $1 * Array(Range.new($2.to_i, $3.to_i)).sample }.                      # A{1,2} becomes A or AA or \d{3} becomes \d\d\d
          gsub(/\((.*?)\)/) {|match| match.gsub(/[\(\)]/, '').split('|').sample }.                                      # (this|that) becomes 'this' or 'that'
          gsub(/\[([^\]]+)\]/) {|match| match.gsub(/(\w\-\w)/) {|range| Array(Range.new(*range.split('-'))).sample } }. # All A-Z inside of [] become C (or X, or whatever)
          gsub(/\[([^\]]+)\]/) {|match| $1.split('').sample }.                                                          # All [ABC] become B (or A or C)
          gsub('\d') {|match| Numbers.sample }.
          gsub('\w') {|match| Letters.sample }
      end

      # Helper for the common approach of grabbing a translation
      # with an array of values and selecting one of them.
      def fetch(key)
        fetched = translate("faker.#{key}")
        fetched = fetched.sample if fetched.respond_to?(:sample)
        if fetched && fetched.match(/^\//) and fetched.match(/\/$/) # A regex
          regexify(fetched)
        else
          fetched
        end
      end

      # Helper for the common approach of grabbing a translation
      # with an array of values and returning all of them.
      def fetch_all(key)
        fetched = translate("faker.#{key}")
        fetched = fetched.last if fetched.size <= 1
        if !fetched.respond_to?(:sample) && fetched.match(/^\//) and fetched.match(/\/$/) # A regex
          regexify(fetched)
        else
          fetched
        end
      end

      # Load formatted strings from the locale, "parsing" them
      # into method calls that can be used to generate a
      # formatted translation: e.g., "#{first_name} #{last_name}".

      def parse(key)
        fetch(key).scan(/(\(?)#\{([A-Za-z]+\.)?([^\}]+)\}([^#]+)?/).map {|prefix, kls, meth, etc|
          # If the token had a class Prefix (e.g., Name.first_name)
          # grab the constant, otherwise use self
          cls = kls ? Faker.const_get(kls.chop) : self

          # If an optional leading parentheses is not present, prefix.should == "", otherwise prefix.should == "("
          # In either case the information will be retained for reconstruction of the string.
          text = prefix

          # If the class has the method, call it, otherwise
          # fetch the transation (i.e., faker.name.first_name)
          text += cls.respond_to?(meth) ? cls.send(meth) : fetch("#{(kls || self).to_s.split('::').last.downcase}.#{meth.downcase}")
          # And tack on spaces, commas, etc. left over in the string
          text += etc.to_s
        }.join
      end

      # Call I18n.translate with our configured locale if no
      # locale is specified
      def translate(*args)
        opts = args.last.is_a?(Hash) ? args.pop : {}
        opts[:locale] ||= Faker::Config.locale
        opts[:raise] = true
        I18n.translate(*(args.push(opts)))
      rescue I18n::MissingTranslationData
        opts = args.last.is_a?(Hash) ? args.pop : {}
        opts[:locale] = :en

        # Super-simple fallback -- fallback to en if the
        # translation was missing.  If the translation isn't
        # in en either, then it will raise again.
        I18n.translate(*(args.push(opts)))
      end

      def flexible(key)
        @flexible_key = key
      end

      # You can add whatever you want to the locale file, and it will get caught here.
      # E.g., in your locale file, create a
      #   name:
      #     girls_name: ["Alice", "Cheryl", "Tatiana"]
      # Then you can call Faker::Name.girls_name and it will act like #first_name
      def method_missing(m, *args, &block)
        super unless @flexible_key

        # Use the alternate form of translate to get a nil rather than a "missing translation" string
        if translation = translate(:faker)[@flexible_key][m]
          translation.respond_to?(:sample) ? translation.sample : translation
        else
          super
        end
      end

      def unique(max_retries = 10_000)
        @unique_generator ||= UniqueGenerator.new(self, max_retries)
      end
    end
  end
end

require 'faker/address'
require 'faker/name'
require 'faker/phone_number'

#=============Starts here================#

def mistakeString str
  #Uncomment to check the correctness of making mistakes
  #puts str + " -- mistake here"
  cc=Random.rand(2)
  case cc
    when 0
      letter1=Random.rand(str.length)
      letter2=Random.rand(str.length)
      temp=str[letter1]
      str[letter1]=str[letter2]
      str[letter2]=temp
    when 1
      str[Random.rand(str.length)+1]=''
  end

  return str
end

def chooseMistake name, state, city, street, zip, phone
  c=Random.rand(6)
  case c
    when 0
      name=mistakeString(name)
    when 1
      state=mistakeString(state)
    when 2
      city=mistakeString(city)
    when 3
      street=mistakeString(street)
    when 4
      zip=mistakeString(zip)
    when 5
      phone=mistakeString(phone)
  end
end

locale=ARGV[0]
counter=ARGV[1].to_i
mistakeChance=ARGV[2] ? (ARGV[2].to_f >= 0 ? ARGV[2].to_f : (raise 'Number of mistakes must be positive.')) : 0
mistakeNumber=mistakeChance*counter
remainder=mistakeNumber%counter
timesNumber=(mistakeNumber/counter).to_i

Faker::Config.locale=locale
country=Faker::Address.default_country

counter.times do |i|
  name=Faker::Name.name
  state=Faker::Address.state
  city=Faker::Address.city
  street=Faker::Address.street_address
  zip=Faker::Address.zip
  phone=Faker::PhoneNumber.phone_number

  if(mistakeNumber >= counter)
    timesNumber.to_i.times do
      chooseMistake(name, state, city, street, zip, phone)
    end
    if(remainder>0)
      chooseMistake(name, state, city, street, zip, phone)
      remainder=remainder-1
    end
  else
    if(i<mistakeNumber)
      chooseMistake(name, state, city, street, zip, phone)
    end
  end

  puts name + "; " + country + "; " + state + "; " + city + "; " + street + "; " + zip + "; " + phone
end