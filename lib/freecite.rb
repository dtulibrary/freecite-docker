require 'CRFPP'
require 'yaml'

class String
	def blank?
		respond_to?(:empty?) ? !!empty? : !self
	end
end

class Array
  def mean
    (size > 0) ? inject(0) { |sum, xx| sum + xx }.to_f / size : 0
  end

  def stddev
    m = mean
    devsum = inject( 0 ) { |ds,x| ds += (x - m)**2 }
    (size > 0) ? (devsum.to_f / size) ** 0.5 : 0
  end
end

module TokenFeatures

  QUOTES = Regexp.escape('"\'”’´‘“`')
  SEPARATORS = Regexp.escape(".;,)")

  def TokenFeatures.read_dict_file(filename)
    dict = {}
    f = File.open(filename, 'r')
    while l = f.gets
      l.strip!
      case l
        when /^\#\# Male/
          mode = 1
        when /^\#\# Female/
          mode = 2
        when /^\#\# Last/
          mode = 4
        when /^\#\# Chinese/
          mode = 4
        when /^\#\# Months/
          mode = 8
        when /^\#\# Place/
          mode = 16
        when /^\#\# Publisher/
          mode = 32
        when (/^\#/)
          # noop
        else
          key = l
          val = 0
          # entry has a probability
          key, val = l.split(/\t/) if l =~ /\t/

          # some words in dict appear in multiple places
          unless dict[key] and dict[key] >= mode
            dict[key] ||= 0
            dict[key] += mode
          end
      end
    end
    f.close
    dict
  end

  DIR = File.dirname(__FILE__)
  DICT = TokenFeatures.read_dict_file("#{DIR}/resources/parsCitDict.txt")
  DICT_FLAGS =
    {'publisherName' =>  32,
     'placeName'     =>  16,
     'monthName'     =>  8,
     'lastName'      =>  4,
     'femaleName'    =>  2,
     'maleName'      =>  1}

  private_class_method :read_dict_file

  def clear
    @possible_editor = nil
    @possible_chapter = nil
    @dict_status = nil
    @is_proceeding = nil
  end

  def last_char(toks, toksnp, tokslcnp, idx)
    case toks[idx][-1,1]
      when /[a-z]/
        'a'
      when /[A-Z]/
        'A'
      when /[0-9]/
        0
      else
        toks[idx][-1,1]
    end
  end

  def first_1_char(toks, toksnp, tokslcnp, idx); toks[idx][0,1]; end
  def first_2_chars(toks, toksnp, tokslcnp, idx); toks[idx][0,2]; end
  def first_3_chars(toks, toksnp, tokslcnp, idx); toks[idx][0,3]; end
  def first_4_chars(toks, toksnp, tokslcnp, idx); toks[idx][0,4]; end
  def first_5_chars(toks, toksnp, tokslcnp, idx); toks[idx][0,5]; end

  def last_1_char(toks, toksnp, tokslcnp, idx); toks[idx][-1,1]; end
  def last_2_chars(toks, toksnp, tokslcnp, idx); toks[idx][-2,2] || toks[idx]; end
  def last_3_chars(toks, toksnp, tokslcnp, idx); toks[idx][-3,3] || toks[idx]; end
  def last_4_chars(toks, toksnp, tokslcnp, idx); toks[idx][-4,4] || toks[idx]; end

  def toklcnp(toks, toksnp, tokslcnp, idx); tokslcnp[idx]; end

  def capitalization(toks, toksnp, tokslcnp, idx)
    case toksnp[idx]
      when /^[A-Z]$/
        "singleCap"
      when /^[A-Z][a-z]+/
        "InitCap"
      when /^[A-Z]+$/
        "AllCap"
      else
        "others"
    end
  end

  def numbers(toks, toksnp, tokslcnp, idx)
    (toks[idx]           =~ /[0-9]\-[0-9]/)          ? "possiblePage" :
      (toks[idx]         =~ /^\D*(19|20)[0-9][0-9]\D*$/)   ? "year"         :
      (toks[idx]         =~ /[0-9]\([0-9]+\)/)       ? "possibleVol"  :
      (toksnp[idx]       =~ /^(19|20)[0-9][0-9]$/)   ? "year"         :
      (toksnp[idx]       =~ /^[0-9]$/)               ? "1dig"         :
      (toksnp[idx]       =~ /^[0-9][0-9]$/)          ? "2dig"         :
      (toksnp[idx]       =~ /^[0-9][0-9][0-9]$/)     ? "3dig"         :
      (toksnp[idx]       =~ /^[0-9]+$/)              ? "4+dig"        :
      (toksnp[idx]       =~ /^[0-9]+(th|st|nd|rd)$/) ? "ordinal"      :
      (toksnp[idx]       =~ /[0-9]/)                 ? "hasDig"       : "nonNum"
  end

  def possible_editor(toks, toksnp, tokslcnp, idx)
    if @possible_editor
      @possible_editor
    else
      @possible_editor =
        (tokslcnp.any? { |t|  %w(ed editor editors eds edited).include?(t)} ?
          "possibleEditors" : "noEditors")
    end
  end

  # if there is possible editor entry and "IN" preceeded by punctuation
  # this citation may be a book chapter
  def possible_chapter(toks, toksnp, tokslcnp, idx)
    if @possible_chapter
      @possible_chapter
    else
      @possible_chapter =
        ((possible_editor(toks, toksnp, tokslcnp, idx) and
        (toks.join(" ") =~ /[\.,;]\s*in[:\s]/i)) ?
          "possibleChapter" : "noChapter")
    end
  end

  def is_proceeding(toks, toksnp, tokslcnp, idx)
    if @is_proceeding
      @is_proceeding
    else
      @is_proceeding =
        (tokslcnp.any? {|t|
          %w( proc proceeding proceedings ).include?(t.strip)
        } ? 'isProc' : 'noProc')
    end
  end

  def is_in(toks, toksnp, tokslcnp, idx)
    ((idx > 0) and
     (idx < (toks.length - 1)) and
     (toksnp[idx+1] =~ /^[A-Z]/) and
     (tokslcnp[idx] == 'in') and
     (toks[idx-1] =~ /[#{SEPARATORS}#{QUOTES}]/))? "inBook" : "notInBook"
  end

  def is_et_al(toks, toksnp, tokslcnp, idx)
    a = false
    a = ((tokslcnp[idx-1] == 'et') and (tokslcnp[idx] == 'al')) if idx > 0
    return a if a

    if idx < toks.length - 1
      a = ((tokslcnp[idx] == 'et') and (tokslcnp[idx+1] == 'al'))
    end

    return (a ? "isEtAl" : "noEtAl")
  end

  def location(toks, toksnp, tokslcnp, idx)
    r = ((idx.to_f / toks.length) * 10).round
  end

  def punct(toks, toksnp, tokslcnp, idx)
    (toks[idx]   =~ /^[\"\'\`]/)                    ? "leadQuote"   :
      (toks[idx] =~ /[\"\'\`][^s]?$/)               ? "endQuote"    :
      (toks[idx] =~ /\-.*\-/)                       ? "multiHyphen" :
      (toks[idx] =~ /[\-\,\:\;]$/)                  ? "contPunct"   :
      (toks[idx] =~ /[\!\?\.\"\']$/)                ? "stopPunct"   :
      (toks[idx] =~ /^[\(\[\{\<].+[\)\]\}\>].?$/)   ? "braces"      :
      (toks[idx] =~ /^[0-9]{2,5}\([0-9]{2,5}\).?$/) ? "possibleVol" : "others"
  end

  def a_is_in_dict(toks, toksnp, tokslcnp, idx)
    ret = {}
    @dict_status = (DICT[tokslcnp[idx]] ? DICT[tokslcnp[idx]] : 0)
  end

  def publisherName(toks, toksnp, tokslcnp, idx)
    (@dict_status & DICT_FLAGS['publisherName']) > 0 ? 'publisherName' : 'noPublisherName'
  end

  def placeName(toks, toksnp, tokslcnp, idx)
    (@dict_status & DICT_FLAGS['placeName']) > 0 ? 'placeName' : 'noPlaceName'
  end

  def monthName(toks, toksnp, tokslcnp, idx)
    (@dict_status & DICT_FLAGS['monthName']) > 0 ? 'monthName' : 'noMonthName'
  end

  def lastName(toks, toksnp, tokslcnp, idx)
    (@dict_status & DICT_FLAGS['lastName']) > 0 ? 'lastName' : 'noLastName'
  end

  def femaleName(toks, toksnp, tokslcnp, idx)
    (@dict_status & DICT_FLAGS['femaleName']) > 0 ? 'femaleName' : 'noFemaleName'
  end

  def maleName(toks, toksnp, tokslcnp, idx)
    (@dict_status & DICT_FLAGS['maleName']) > 0 ? 'maleName' : 'noMaleName'
  end

end

module Postprocessor

  def normalize_fields(citation_hsh)
    citation_hsh.keys.each {|key| self.send("normalize_#{key}", citation_hsh) }
    citation_hsh
  end

  def method_missing(m, args)
    # Call normalize on any fields that don't have their own normalization
    # method defined
    if m.to_s =~ /^normalize/
      m.to_s =~ /normalize_(.*)$/
      normalize($1, args)
    else super
    end
  end

  # default normalization function for all fields that do not have their
  # own normalization
  # Strip any leading and/or trailing punctuation
  def normalize(key, hsh)
    hsh[key].gsub!(/^[^A-Za-z0-9]+/, '')
    hsh[key].gsub!(/[^A-Za-z0-9]+$/, '')
    hsh
  end

  ##
  # Tries to split the author tokens into individual author names
  # and then normalizes these names individually.  Returns a
  # list of author names.
  ##
  def normalize_author(hsh)
    str = hsh['author']
    tokens = repair_and_tokenize_author_text(str)
    authors = []
    current_auth = []
    begin_auth = 1
    tokens.each {|tok|
      if tok =~ /^(&|and)$/i
        if !current_auth.empty?
          auth = normalize_author_name(current_auth)
          authors << auth
        end
        current_auth = []
        begin_auth = 1
        next
      end
      if begin_auth > 0
        current_auth << tok
        begin_auth = 0
        next
      end
      if tok =~ /,$/
        current_auth << tok
        if !current_auth.empty?
          auth = normalize_author_name(current_auth)
          authors << auth
          current_auth = []
          begin_auth = 1
        end
      else
        current_auth << tok
      end
    }
    if !current_auth.empty?
      auth = normalize_author_name(current_auth)
      authors << auth unless auth.strip == "-"
    end
    hsh['authors'] = authors
    hsh
  end

  def normalize_date(hsh)
    str = hsh['date']
    if str =~ /(\d{4})/
      year = $1.to_i
      current_year = Time.now.year
      if year <= current_year+3
        ret = year
        hsh['year'] = ret
      else
        ret = nil
      end
    end
    hsh['date'] = ret
    hsh
  end

  def normalize_volume(hsh)
    # If there are two numbers, they are volume and number.
    # e.g. "23(2)", "Vol. 23, No. 3" etc...
    if hsh['volume'] =~ /\D*(\d+)\D+(\d+)/i
      hsh['volume'] = $1
      hsh['number'] = $2
    # Otherwise, just pull out a number and hope that it's the volume
    elsif hsh['volume'] =~ /(\d+)/
      hsh['volume'] = $1
    end
    hsh
  end

  ##
  # Normalizes page fields into the form "start--end".  If the page
  # field does not appear to be in a standard form, does nothing.
  ##
  def normalize_pages(hsh)
    # "vol.issue (year):pp"
    case hsh['pages']
    when /(\d+) (?: \.(\d+))? (?: \( (\d\d\d\d) \))? : (\d.*)/x
      hsh['volume'] = $1
      hsh['number'] = $2 if $2
      hsh['year'] = $3 if $3
      hsh['pages'] = $4
    end

    case hsh['pages']
    when  /(\d+)[^\d]+(\d+)/
      hsh['pages'] = "#{$1}--#{$2}"
    when  /(\d+)/
      hsh['pages'] = $1
    end
    hsh
  end

  def repair_and_tokenize_author_text(author_text)
    # Repair obvious parse errors and weird notations.
    author_text.sub!(/et\.? al\.?.*$/, '')
    # FIXME: maybe I'm mis-understanding Perl regular expressions, but
    # this pattern from ParseCit appears to do the Wrong Thing:
    # author_text.sub!(/^.*?[a-zA-Z][a-zA-Z]+\. /, '')
    author_text.gsub!(/\(.*?\)/, '')
    author_text.gsub!(/^.*?\)\.?/, '')
    author_text.gsub!(/\(.*?$/, '')
    author_text.gsub!(/\[.*?\]/, '')
    author_text.gsub!(/^.*?\]\.?/, '')
    author_text.gsub!(/\[.*?$/, '')
    author_text.gsub!(/;/, ',')
    author_text.gsub!(/,/, ', ')
    author_text.gsub!(/\:/, ' ')
    author_text.gsub!(/[\:\"\<\>\/\?\{\}\[\]\+\=\(\)\*\^\%\$\#\@\!\~\_]/, '')
    author_text = join_multi_word_names(author_text)

    orig_tokens = author_text.split(/\s+/)
    tokens = []
    last = false
    orig_tokens.each_with_index {|tok, i|
      if tok !~ /[A-Za-z&]/
        if i < orig_tokens.length/2
          tokens = []
          next
        else
          last = true
        end
      end
      if (tok =~ /^(jr|sr|ph\.?d|m\.?d|esq)\.?\,?$/i and
          tokens.last =~ /\,$/) or
          tok =~ /^[IVX][IVX]+\.?\,?$/

        next
      end
      tokens << tok
      break if last
    }
    tokens
  end # repair_and_tokenize_author_text

  # Insert underscores to join name particles. i.e.
  # Jon de Groote ---> Jon de_Groote
  def join_multi_word_names(author_text)
    author_text.gsub(/\b((?:van|von|der|den|de|di|le|el))\s/si) {
      "#{$1}_"
    }
  end

  ##
  # Tries to normalize an individual author name into the form
  # "First Middle Last", without punctuation.
  ##
  def normalize_author_name(auth_toks)
    return '' if auth_toks.empty?
    str = auth_toks.join(" ")
    if str =~ /(.+),\s*(.+)/
      str = "#{$1} #{$2}"
    end
    str.gsub!(/\.\-/, '-')
    str.gsub!(/[\,\.]/, ' ')
    str.gsub!(/  +/, ' ')
    str.strip!

    if (str =~ /^[^\s][^\s]+(\s+[^\s]|\s+[^\s]\-[^\s])+$/)
      new_toks = str.split(/\s+/)
      new_order = new_toks[1...new_toks.length];
      new_order << new_toks[0]
      str = new_order.join(" ")
    end
    return str
  end

end

class CRFParser


  attr_reader :feature_order
  attr_reader :token_features

  include TokenFeatures
  include Postprocessor

  DIR = File.dirname(__FILE__)
  TAGGED_REFERENCES = "#{DIR}/resources/trainingdata/tagged_references.txt"
  TRAINING_DATA = "#{DIR}/resources/trainingdata/training_data.txt"
  MODEL_FILE = "#{DIR}/resources/model"
  TEMPLATE_FILE = "#{DIR}/resources/parsCit.template"

  # Feature functions must be performed in alphabetical order, since
  # later functions may depend on earlier ones.
  # If you want to specify a specific output order, do so in a yaml file in
  # config. See ../config/parscit_features.yml as an example
  # You may also use this config file to specify a subset of features to use
  # Just be careful not to exclude any functions that included functions
  # depend on
  def initialize(config_file="#{DIR}/../config/parscit_features.yml")
    if config_file
      f = File.open(config_file, 'r')
      hsh = YAML::load( f )
      @feature_order = hsh["feature_order"].map(&:to_sym)
      @token_features = hsh["feature_order"].sort.map(&:to_sym)
    else
      @token_features = (TokenFeatures.instance_methods).sort.map(&:to_sym)
      @token_features.delete :clear
      @feature_order = @token_features
    end
  end

  def model
    @model ||= CRFPP::Tagger.new("-m #{MODEL_FILE}");
  end

  def parse_string(str)
    features = str_2_features(str)
    tags = eval_crfpp(features)
    toks = str.scan(/\S*\s*/)
    ret = {}
    tags.each_with_index {|t, i|
      (ret[t] ||= '') << toks[i]
    }
    normalize_fields(ret)
    ret['raw_string'] = str
    ret
  end

  def eval_crfpp(feat_seq)
    model.clear
    #num_lines = 0
    feat_seq.each {|vec|
      line = vec.join(" ").strip
      raise unless model.add(line)
      #num_lines += 1
    }
    raise unless model.parse
    tags = []
    feat_seq.length.times {|i|
      tags << model.y2(i)
    }
    tags
  end

  def strip_punct(str)
    toknp = str.gsub(/[^\w]/, '')
    toknp = "EMPTY" if toknp.blank?
    toknp
  end

  def prepare_token_data(cstr, training=false)
    cstr.strip!
    # split the string on whitespace and calculate features on each token
    tokens_and_tags = cstr.split(/\s+/)
    tag = nil
    self.clear

    # strip out any tags
    tokens = tokens_and_tags.reject {|t| t =~ /^<[\/]{0,1}([a-z]+)>$/}

    # strip tokens of punctuation
    tokensnp = tokens.map {|t| strip_punct(t) }

    # downcase stripped tokens
    tokenslcnp = tokensnp.map {|t| t == "EMPTY" ? "EMPTY" : t.downcase }
    return [tokens_and_tags, tokens, tokensnp, tokenslcnp]
  end

  # calculate features on the full citation string
  def str_2_features(cstr, training=false)
    features = []
    tokens_and_tags, tokens, tokensnp, tokenslcnp = prepare_token_data(cstr, training)
    toki = 0
    tag = nil
    tokens_and_tags.each_with_index {|tok, i|
      # if this is training data, grab the mark-up tag and then skip it
      if training
        if tok =~ /^<([a-z]+)>$/
          tag = $1
          next
        elsif tok =~ /^<\/([a-z]+)>$/
          tok = nil
          raise TrainingError, "Mark-up tag mismatch #{tag} != #{$1}\n#{cstr}" if $1 != tag
          next
        end
      end
      feats = {}


      # If we are training, there should always be a tag defined
      if training && tok.nil?
        raise TrainingError, "Incorrect mark-up:\n #{cstr}"
      end
      @token_features.each {|f|
        feats[f] = self.send(f, tokens, tokensnp, tokenslcnp, toki)
      }
      toki += 1

      features << [tok]
      @feature_order.each {|f| features.last << feats[f]}
      features.last << tag if training
    }
    return features
  end

  def write_training_file(tagged_refs=TAGGED_REFERENCES,
    training_data=TRAINING_DATA)

    fin = File.open(tagged_refs, 'r')
    fout = File.open(training_data, 'w')
    x = 0
    while l = fin.gets
      puts "processed a line #{x+=1}"
      data = str_2_features(l.strip, true)
      data.each {|line| fout.write("#{line.join(" ")}\n") }
      fout.write("\n")
    end

    fin.close
    fout.flush
    fout.close
  end

  def train(tagged_refs=TAGGED_REFERENCES, model=MODEL_FILE,
    template=TEMPLATE_FILE, training_data=nil)

    if training_data.nil?
      training_data = TRAINING_DATA
      write_training_file(tagged_refs, training_data)
    end
    puts "crf_learn #{template} #{training_data} #{model}"
    `crf_learn #{template} #{training_data} #{model}`
  end

end

class TrainingError < Exception; end
