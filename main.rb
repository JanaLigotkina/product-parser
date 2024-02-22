#!/usr/bin/env ruby

require 'bundler/inline'
require 'open-uri'
require 'open3'
require 'ruby-progressbar'
require 'concurrent'

gemfile do
  source 'https://rubygems.org'

  ruby '>= 3.0.0'

  gem 'csv'
  gem 'nokogiri'
  gem 'rainbow'
  gem 'thor'
  gem 'ruby-progressbar'
  gem 'concurrent-ruby'
end

Product = Struct.new(:name, :price, :image)

module Xpath
  PRODUCT_CONTAINER_XPATH = '//div[contains(@class, "product-container")]'.freeze
  PRODUCT_URL_XPATH = './/a[@class="product_img_link pro_img_hover_scale product-list-category-img"]/@href'.freeze
  BASE_NAME_XPATH = '//div[@itemtype="http://schema.org/Product"]/meta[@itemprop="name"]/@content'.freeze
  IMAGES_XPATH = '//div[@itemtype="http://schema.org/Product"]/link[@itemprop="image"]/@href'.freeze
  VARIANTS_XPATH = '//ul[@class="attribute_radio_list pundaline-variations"]/li'.freeze
  VARIANT_NAME_XPATH = './/span[@class="radio_label"]'.freeze
  PRICE_XPATH = './/span[@class="price_comb"]'.freeze
end

module Parser
  def parse(url)
    raise NotImplementedError, 'You must implement the parse method'
  end
end

module Logging
  def create_progress_bar(total)
    ProgressBar.create(total: total, format: '%a %bᗧ%i %p%% %t')
  end

  def log(message)
    stdout, status = Open3.capture2('echo', message)
    puts Rainbow(stdout).blue if status.success?
  end
end

class ProductList
  attr_accessor :url, :products

  def initialize(url)
    @url = url
    @products = []
  end

  def add_product(product)
    @products << product
  end
end

class ProductListPageParser
  include Xpath
  include Parser
  include Logging

  attr_reader :page_number

  def initialize(product_page_parser)
    @product_page_parser = product_page_parser
    @page_number = 1
  end

  def parse(product_list)
    product_list.products.clear
    doc = fetch_page(product_list)

    return nil if doc.nil?

    parse_products(doc, product_list)
    increment_page_number
    products_empty?(product_list)
  end

  private

  def fetch_page(product_list)
    sleep(1)
    open_url = URI.open(product_list.url)
    final_url = open_url.base_uri.to_s

    return nil if final_url != product_list.url

    Nokogiri::HTML(open_url)
  end

  def parse_products(doc, product_list)
    products = doc.xpath(PRODUCT_CONTAINER_XPATH)
    progressbar = create_progress_bar(products.size)

    pool = Concurrent::FixedThreadPool.new(10) # 10 threads

    products.each do |product|
      pool.post do
        product_url = product.xpath(PRODUCT_URL_XPATH).text.strip
        @product_page_parser.parse(product_url).each do |product|
          product_list.add_product(product)
        end
        progressbar.increment
      end
    end

    pool.shutdown
    pool.wait_for_termination

    log("Products from page №#{@page_number} are recorded")
  end

  def increment_page_number
    @page_number += 1
  end

  def products_empty?(product_list)
    product_list.products.empty? ? nil : product_list.products
  end
end

class ProductPageParser
  include Xpath
  include Parser

  def parse(url)
    doc = Nokogiri::HTML(URI.open(url))

    base_name = doc.xpath(BASE_NAME_XPATH).text
    images = doc.xpath(IMAGES_XPATH)

    variants = []

    doc.xpath(VARIANTS_XPATH).each do |variant|
      variant_name = variant.xpath(VARIANT_NAME_XPATH).text.strip
      price = variant.xpath(PRICE_XPATH).text.strip
      name = "#{base_name} - #{variant_name}"

      variants << Product.new(name, price, images[0].text)
    end

    variants
  end
end

class FileWriter
  def initialize(filename)
    @filename = filename
  end

  def write(product_list, filename)
    create_file unless File.exist?(filename)

    CSV.open(filename, 'a') do |csv|
      product_list.products.each do |product|
        csv << [product.name, product.price, product.image]
      end
    end
  end

  private

  def create_file
    CSV.open(@filename, 'wb') do |csv|
      csv << %w[Name Price Image]
    end
  end
end

class DataProcessor
  def initialize(product_list_parser, file_writer)
    @product_list_parser = product_list_parser
    @file_writer = file_writer
  end

  def record_to_file(product_list, category_url, filename)
    loop do
      break if @product_list_parser.parse(product_list).nil?

      @file_writer.write(product_list, filename)

      product_list.url = "#{category_url}?p=#{@product_list_parser.page_number}"
    end
  end
end

class ProductParserCLI < Thor
  # Example start:
  # ruby main.rb record "https://www.petsonic.com/dermatitis-y-problemas-piel-para-perros/" "pet_products.csv"
  desc 'record URL FILENAME', 'Process a category page and write the results to a file'

  def record(url, filename)
    say Rainbow("Picking up products from: `#{url}`").blue
    say Rainbow("Creating a file with the name `#{filename}`").blue

    product_list = ProductList.new(url)
    product_page_parser = ProductPageParser.new
    product_list_parser = ProductListPageParser.new(product_page_parser)
    file_writer = FileWriter.new(filename)

    data_processor = DataProcessor.new(product_list_parser, file_writer)
    data_processor.record_to_file(product_list, url, filename)

    say Rainbow("Done! All products added. Check the file for the results \n`#{File.absolute_path(filename)}`").green
  end
end

ProductParserCLI.start(ARGV)
