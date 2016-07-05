require 'freecite'

DIR = File.dirname(__FILE__)
`mkdir -p #{DIR}/data`
TAGGED_REFERENCES = "#{DIR}/../lib/resources/trainingdata/tagged_references.txt"
REFS_PREFIX = "training_refs_"
DATA_PREFIX = "training_data_"
OUTPUT_FILE = "#{DIR}/data/output.txt"
TRAINING_DATA = "#{DIR}/data/training_data.txt"
TRAINING_REFS = "#{DIR}/data/training_refs.txt"
MODEL_FILE = "#{DIR}/data/model"
TEMPLATE_FILE = "#{DIR}/../lib/resources/parsCit.template"
TESTING_DATA = "#{DIR}/data/testing_data.txt"
ANALYSIS_FILE = "#{DIR}/data/analysis.csv"

describe "model test" do
  before(:each) do
    @crf = CRFParser.new
  end

  # Disabled - Evaluation of CRF model - Takes a long time to run
  xit "run model test" do
    generate_data = lambda do |k = 10|
      testpct = k/100.0
      lines = []
      k.times { lines << [] }
      f = File.open(TAGGED_REFERENCES, 'r')
      while line = f.gets
        lines[((rand * k) % k).floor] << line.strip
      end
      f.close

      lines.each_with_index {|ll, i|
        f = File.open("#{DIR}/data/#{REFS_PREFIX}#{i}.txt", 'w')
        f.write(ll.join("\n"))
        f.flush
        f.close
        @crf.write_training_file("#{DIR}/data/#{REFS_PREFIX}#{i}.txt",
                                 "#{DIR}/data/#{DATA_PREFIX}#{i}.txt")
      }
    end

    train = lambda do
      @crf.train(TRAINING_REFS, MODEL_FILE, TEMPLATE_FILE, TRAINING_DATA)
    end

    test = lambda do
      str = "crf_test -m #{MODEL_FILE} #{TESTING_DATA} >> #{OUTPUT_FILE}"
      puts str
      `#{str}`
    end

    cross_validate = lambda do |k = 10|
      generate_data.call(k)
      # clear the output file
      f = File.open(OUTPUT_FILE, 'w')
      f.close
      k.times {|i|
        puts "Performing #{i+1}th iteration of #{k}-fold cross validation"
        # generate training refs
        `rm #{TRAINING_DATA}; touch #{TRAINING_DATA};`
        k.times {|j|
          next if j == i
          `cat #{DIR}/data/#{DATA_PREFIX}#{j}.txt >> #{TRAINING_DATA}`
        }
        puts "Training model"
        train.call
        `cat #{DIR}/data/#{DATA_PREFIX}#{i}.txt > #{TESTING_DATA}`
        puts "Testing model"
        test.call
      }
    end

    analyze = lambda do |k = 10|
      new_hash = lambda do |labels|
        h = Hash.new
        labels.each {|lab1|
          h[lab1] = {}
          labels.each {|lab2|
            h[lab1][lab2] = 0
          }
        }
        h
      end

      # get the size of the corpus
      corpus_size = `wc #{TAGGED_REFERENCES}`.split.first

      # go through all training/testing data to get complete list of output tags
      labels = {}
      [TRAINING_DATA, TESTING_DATA].each {|fn|
        f = File.open(fn, 'r')
        while l = f.gets
          next if l.strip.blank?
          labels[l.strip.split.last] = true
        end
        f.close
      }
      labels = labels.keys.sort
      puts "got labels:\n#{labels.join("\n")}"

      # reopen and go through the files again
      # for each reference, populate a confusion matrix hash
      references = []
      testf = File.open(OUTPUT_FILE, 'r')
      ref = new_hash.call(labels)
      while testl = testf.gets
        if testl.strip.blank?
          references << ref
          ref = new_hash.call(labels)
          next
        end
        w = testl.strip.split
        te = w[-1]
        tr = w[-2]
        puts "#{te} #{tr}"
        ref[tr][te] += 1
      end
      testf.close

      # print results to a file
      f = File.open(ANALYSIS_FILE, 'w')
      f.write "Test run on:,#{Time.now}\n"
      f.write "K-fold x-validation:,#{k}\n"
      f.write "Corpus size:,#{corpus_size}\n\n"

      # aggregate results in total hash
      total = {}
      labels.each {|trl|
        labels.each {|tel|
            total[trl] ||= {}
            total[trl][tel] = references.map {|r| r[trl][tel]}.inject(0) { |sum, r| sum + r }
        }
      }

      # print a confusion matrix
      f.write 'truth\test,'
      f.write labels.join(',')
      f.write "\n"
      # first, by counts
      labels.each {|trl|
        f.write "#{trl},"
        f.write( labels.map {|tel| total[trl][tel] }.join(',') )
        f.write "\n"
      }
      # then by percent
      labels.each {|trl|
        f.write "#{trl},"
        f.write labels.map{|tel| total[trl][tel]/total[trl].values.inject(0) { |sum, xx| sum + xx }.to_f }.join(',')
        f.write "\n"
      }

      # precision and recal by label
      f.write "\n"
      f.write "Label,Precision,Recall,F-measure\n"
      labels.each {|trl|
        p = total[trl][trl].to_f / labels.map{|l| total[l][trl]}.inject(0) { |sum, xx| sum + xx }
        r = total[trl][trl].to_f / total[trl].values.inject(0) { |sum, xx| sum + xx }
        fs = (2*p*r)/(p+r)
        f.write "#{trl},#{p},#{r},#{fs}\n"
      }

      # get the average accuracy-per-reference
      perfect = 0
      avgs = references.map {|r|
        n = labels.map {|label| r[label][label] }.inject(0) { |sum, xx| sum + xx }
        d = labels.map {|lab| r[lab].values.inject(0) { |sum, xx| sum + xx } }.inject(0) { |sum, xx| sum + xx }
        perfect += 1 if n == d
        n.to_f / d
      }
      f.write "\nAverage accuracy by reference:,#{avgs.mean}\n"
      f.write "STD of Average accuracy by reference:,#{avgs.stddev}\n"

      # number of perfectly parsed references
      f.write "Perfect parses:,#{perfect},#{perfect.to_f/references.length}\n"

      # Total accuracy
      n = labels.map {|lab| total[lab][lab]}.inject(0) { |sum, xx| sum + xx }
      d = labels.map {|lab1| labels.map {|lab2| total[lab1][lab2]}.inject(0) { |sum, xx| sum + xx } }.inject(0) { |sum, xx| sum + xx }
      f.write "Accuracy:, #{n/d.to_f}\n"

      f.flush
      f.close

      return n/d.to_f
    end

    benchmark = lambda do
      return # TODO TLNI
      refs = []
      f = File.open(TRAINING_REFS, 'r')
      while line = f.gets
        refs << line.strip
      end
      # strip out tags
      refs.map! {|s| s.gsub(/<[^>]*>/, '')}
      # parse one string, since the lexicon is lazily evaluated
      Citation.create_from_string(refs.first)
      time = Benchmark.measure {
        refs.each {|ref| Citation.create_from_string(ref) }
      }
      return (time.real / refs.length.to_f)
    end

    k = 10
    cross_validate.call(k)
    accuracy = analyze.call(k)
    time = benchmark.call
    `echo "Average time per parse:,#{time}\n" >> #{ANALYSIS_FILE}`
  end
end

describe "CRFParser" do
  before(:each) do
    @crfparser = CRFParser.new(false)
    @ref = " W. H. Enright.   Improving the efficiency of matrix operations in the numerical solution of stiff ordinary differential equations.   ACM Trans. Math. Softw.,   4(2),   127-136,   June 1978. "
    @tokens_and_tags, @tokens, @tokensnp, @tokenslcnp =
      @crfparser.prepare_token_data(@ref.strip)
  end

  it "last_char" do
    pairs = [[['woefij'], 'a'],
     [['weofiw234809*&^*oeA'], 'A'],
     [['D'], 'A'],
     [['Da'], 'a'],
     [['1t'], 'a'],
     [['t'], 'a'],
     [['*'], '*'],
     [['!@#$%^&*('], '('],
     [['t1'], 0],
     [['1'], 0]]

     pairs.each {|a, b|
       expect(@crfparser.last_char(a, a, a, 0)).to eql(b)
     }
  end

  it "first char" do
    pairs = [[['woefij'], 'w'],
     [['weofiw234809*&^*oeA'], 'w'],
     [['D'], 'D'],
     [['Da'], 'D'],
     [['1t'], '1'],
     [['t'], 't'],
     [['*'], '*'],
     [['!@#$%^&*('], '!'],
     [['t1'], 't'],
     [['1'], '1']]

     pairs.each {|a, b|
       expect(@crfparser.first_1_char(a, a, a, 0)).to eq(b)
     }
  end

  it "first two chars" do
    pairs = [[['woefij'], 'wo'],
     [['weofiw234809*&^*oeA'], 'we'],
     [['D'], 'D'],
     [['Da'], 'Da'],
     [['1t'], '1t'],
     [['t'], 't'],
     [['*'], '*'],
     [['!@#$%^&*('], '!@'],
     [['t1'], 't1'],
     [['1'], '1']]

     pairs.each {|a, b|
       expect(@crfparser.first_2_chars(a, a, a, 0)).to eq(b)
     }
  end

  it "first three chars" do
    pairs = [[['woefij'], 'woe'],
     [['weofiw234809*&^*oeA'], 'weo'],
     [['D'], 'D'],
     [['Da'], 'Da'],
     [['1t'], '1t'],
     [['t'], 't'],
     [['*'], '*'],
     [['!@#$%^&*('], '!@#'],
     [['t1'], 't1'],
     [['1'], '1']]

     pairs.each {|a, b|
       expect(@crfparser.first_3_chars(a, a, a, 0)).to eq(b)
     }
  end

  it "first four chars" do
    pairs = [[['woefij'], 'woef'],
     [['weofiw234809*&^*oeA'], 'weof'],
     [['D'], 'D'],
     [['Da'], 'Da'],
     [['Dax0'], 'Dax0'],
     [['1t'], '1t'],
     [['t'], 't'],
     [['*'], '*'],
     [['!@#$%^&*('], '!@#$'],
     [['t1'], 't1'],
     [['1'], '1']]

     pairs.each {|a, b|
       expect(@crfparser.first_4_chars(a, a, a, 0)).to eq(b)
     }
  end

  it "test_first_5_chars" do
    pairs = [[['woefij'], 'woefi'],
     [['weofiw234809*&^*oeA'], 'weofi'],
     [['D'], 'D'],
     [['DadaX'], 'DadaX'],
     [['Da'], 'Da'],
     [['Dax0'], 'Dax0'],
     [['1t'], '1t'],
     [['t'], 't'],
     [['*'], '*'],
     [['!@#$%^&*('], '!@#$%'],
     [['t1'], 't1'],
     [['1'], '1']]

     pairs.each {|a, b|
       expect(@crfparser.first_5_chars(a, a, a, 0)).to eq(b)
     }
  end

  it "last_1_char" do
    pairs = [[['woefij'], 'j'],
     [['weofiw234809*&^*oeA'], 'A'],
     [['D'], 'D'],
     [['DadaX'], 'X'],
     [['Da'], 'a'],
     [['Dax0'], '0'],
     [['1t'], 't'],
     [['t'], 't'],
     [['*'], '*'],
     [['!@#$%^&*('], '('],
     [['t1'], '1'],
     [['1'], '1']]

     pairs.each {|a, b|
       expect(@crfparser.last_1_char(a, a, a, 0)).to eq(b)
     }
  end

  it "last_2_chars" do
    pairs = [[['woefij'], 'ij'],
     [['weofiw234809*&^*oeA'], 'eA'],
     [['D'], 'D'],
     [['DadaX'], 'aX'],
     [['Da'], 'Da'],
     [['Dax0'], 'x0'],
     [['1t'], '1t'],
     [['t'], 't'],
     [['*'], '*'],
     [['!@#$%^&*('], '*('],
     [['t1'], 't1'],
     [['1'], '1']]

     pairs.each {|a, b|
       expect(@crfparser.last_2_chars(a, a, a, 0)).to eq(b)
     }
  end

  it "last_3_chars" do
    pairs = [[['woefij'], 'fij'],
     [['weofiw234809*&^*oeA'], 'oeA'],
     [['D'], 'D'],
     [['DadaX'], 'daX'],
     [['Da'], 'Da'],
     [['Dax0'], 'ax0'],
     [['1t'], '1t'],
     [['t'], 't'],
     [['*'], '*'],
     [['!@#$%^&*('], '&*('],
     [['t1'], 't1'],
     [['1'], '1']]

     pairs.each {|a, b|
       expect(@crfparser.last_3_chars(a, a, a, 0)).to eq(b)
     }
  end

  it "last_4_chars" do
    pairs = [[['woefij'], 'efij'],
     [['weofiw234809*&^*oeA'], '*oeA'],
     [['D'], 'D'],
     [['DadaX'], 'adaX'],
     [['Da'], 'Da'],
     [['Dax0'], 'Dax0'],
     [['1t'], '1t'],
     [['t'], 't'],
     [['*'], '*'],
     [['!@#$%^&*('], '^&*('],
     [['t1'], 't1'],
     [['1'], '1']]

     pairs.each {|a, b|
       expect(@crfparser.last_4_chars(a, a, a, 0)).to eq(b)
     }
  end

  it "capitalization" do
    pairs = [[["W"], 'singleCap'],
     [["Enright"], 'InitCap'],
     [["IMPROVING"], 'AllCap'],
     [["ThE234"], 'InitCap'],
     [["efficiency"], 'others'],
     [["1978"], 'others']]
     pairs.each {|a, b|
       expect(@crfparser.capitalization(a, a, a, 0)).to eq(b)
     }
  end

  it "numbers" do
    pairs =
      [[['12-34'], 'possiblePage'],
       [['19-99'], 'possiblePage'],
       [['19(99):'], 'possibleVol'],
       [['19(99)'], 'possibleVol'],
       [['(8999)'], '4+dig'],
       [['(1999)'], 'year'],
       [['(2999)23094'], '4+dig'],
       [['wer(299923094'], 'hasDig'],
       [['2304$%^&89ddd=)'], 'hasDig'],
       [['2304$%^&89=)'], '4+dig'],
       [['3$%^&'], '1dig'],
       [['3st'], 'ordinal'],
       [['3rd'], 'ordinal'],
       [['989u83rd'], 'hasDig'],
       [['.2.5'], '2dig'],
       [['1.2.5'], '3dig'],
       [['(1999a)'], 'year'],
       [['a1a'], 'hasDig'],
       [['awef20.09woeifj'], 'hasDig'],
       [['awef2009woeifj'], 'year']]

    pairs.each {|a, b|
      s = [@crfparser.strip_punct(a.first)]
      expect(@crfparser.numbers(a, s, s, 0)).to eq(b)
    }
  end

  it "possible_editor" do
    ee = %w(ed editor editors eds edited)
    ee.each {|e|
      @crfparser.clear
      expect(@crfparser.possible_editor([e], [e], [e], 0)).to eq("possibleEditors")
    }

    @crfparser.possible_editor([ee], [ee], [ee], 0)
    e = @crfparser.possible_editor(["foo"], ["foo"], ["foo"], 0)
    expect(e).to eq("possibleEditors")

    @crfparser.clear
    ee = %w(foo bar 123SFOIEJ EDITUR)
    expect(@crfparser.possible_editor(ee, ee, ee, 0)).to eq("noEditors")
  end
end
