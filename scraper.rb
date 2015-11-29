require 'rubygems'
require 'scraperwiki'
require 'nokogiri'
require 'yaml'
require 'html_to_plain_text'
require 'active_support/core_ext/string'
require 'pdf-reader'
require 'open-uri'

module Scraper
  module_function

  def config
    @config ||= YAML.load(File.read('./config.yml'))
  end

  def expand_uri(path)
    "#{config['base_uri']}/#{path}"
  end
end

class Page < Struct.new(:uri)
  def doc
    @doc ||= Nokogiri::HTML(ScraperWiki.scrape(uri))
  end
end

class Calendar < Page
  def session_uris
    doc.css('.smc_datatype_si').map{ |n|
      Scraper.expand_uri(n['href'])
    }
  end
end

class Session < Page
  def papers
    doc.css('.smc_datatype_vo').map{ |n|
      uri = Scraper.expand_uri(n['href'])
      Paper.new(uri, attributes: extra_page_attributes(n))
    }
  end

  private

  def extra_page_attributes(node)
    # TODO: Fetch resolution
    # require 'pry'
    # page_row =  node.parent.parent
    # if page_row.css('td:contains("Beschluss:")').first
    #   {
    #     resolution:
    #   }
    # end
    {}
  end
end

class Paper < Page
  def initialize(uri, attributes: {})
    super(uri)
    @predefined_attributes = attributes
    puts "Load Page #{uri}"
  end

  def reference
    doc.css('#smctablevorgang .smctablehead:contains("Name") ~ td').text.squish
  end

  def name
    doc.css('#smctablevorgang .smctablehead:contains("Datum") ~ td').text.squish
  end

  def body
    # TODO: What's the body here?
    'Halle'
  end

  def content
    path = doc.css('.smcdocbox a:contains("Beschlussvorlage")').first['href']
    reader = PDF::Reader.new(open(Scraper.expand_uri(path)))
    reader.pages.map(&:text).join('\n')
  end

  def resolution
  end

  def scraped_at
    Time.now
  end

  def published_at
    date = doc.css('#smctablevorgang .smctablehead:contains("Datum") ~ td').text.squish
    Date.parse(date)
  end

  def paper_type
    doc.css('#smctablevorgang .smctablehead:contains("Art") ~ td').text.squish
  end

  def originator
  end

  def under_direction_of
  end

  def attributes
    @attributes ||= {
      id: uri,
      url: uri,
      reference: reference,
      name: name,
      body: body,
      content: content,
      resolution: resolution,
      scraped_at: scraped_at,
      published_at: published_at,
      paper_type: paper_type,
      originator: originator,
      under_direction_of: under_direction_of,
    }.merge!(@predefined_attributes)
  end
end

ScraperWiki.config = { db: 'data.sqlite' }

session_calendar_uri = Scraper.expand_uri(Scraper.config['session_calendar_path'])
calendar = Calendar.new(session_calendar_uri)
calendar.session_uris.each do |uri|
  session = Session.new(uri)
  session.papers.each do |paper|
    ScraperWiki.save_sqlite([:id], paper.attributes, 'data')
  end
end
