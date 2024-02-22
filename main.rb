#!/usr/bin/env ruby

require 'bundler/inline'
require 'open-uri'

gemfile do
  source 'https://rubygems.org'

  ruby '>= 3.0.0'

  gem 'csv'
  gem 'nokogiri'
  gem 'thor'
end

BASE_URL = 'https://www.petsonic.com/dermatitis-y-problemas-piel-para-perros/'.freeze
CSV_FILENAME = 'pet_products.csv'.freeze

PRODUCT_CONTAINER_XPATH = '//div[contains(@class, "product-container")]'.freeze
PRODUCT_URL_XPATH = './/a[@class="product_img_link pro_img_hover_scale product-list-category-img"]/@href'.freeze
BASE_NAME_XPATH = '//div[@itemtype="http://schema.org/Product"]/meta[@itemprop="name"]/@content'.freeze
IMAGES_XPATH = '//div[@itemtype="http://schema.org/Product"]/link[@itemprop="image"]/@href'.freeze
VARIANTS_XPATH = '//ul[@class="attribute_radio_list pundaline-variations"]/li'.freeze
VARIANT_NAME_XPATH = './/span[@class="radio_label"]'.freeze
PRICE_XPATH = './/span[@class="price_comb"]'.freeze

class Product
  attr_accessor :name, :price, :image

  def initialize(name, price, image)
    @name = name
    @price = price
    @image = image
  end
end

class Category
  attr_accessor :url, :products

  def initialize(url)
    @url = url
    @products = []
  end

  def add_product(product)
    @products << product
  end
end

class Parser
  def initialize
    @page_number = 1
  end

  def parse_category_page(category)
    category.products.clear
    sleep(1)
    open_url = URI.open(category.url)
    final_url = open_url.base_uri.to_s

    return nil if final_url != category.url
    doc = Nokogiri::HTML(open_url)

    doc.xpath(PRODUCT_CONTAINER_XPATH).each do |product|
      product_url = product.xpath(PRODUCT_URL_XPATH).text.strip
      parse_product_page(product_url).each do |product|
        category.add_product(product)
      end
    end

    category.products.empty? ? nil : category.products
  end

  def parse_product_page(url)
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

  def write_to_csv(category, filename)
    CSV.open(filename, 'a') do |csv|
      category.products.each do |product|
        csv << [product.name, product.price, product.image]
      end
    end
  end

  def record(category_url, filename)
    category = Category.new(category_url)

    loop do
      break if parse_category_page(category).nil?

      write_to_csv(category, filename)

      @page_number += 1
      category.url = "#{category_url}?p=#{@page_number}"
    end
  end
end

class ProductParserCLI < Thor
  # Example start:
  # ruby main.rb record "https://www.petsonic.com/dermatitis-y-problemas-piel-para-perros/" "pet_products.csv"
  desc 'record URL FILENAME', 'Process a category page and write the results to a file'
  def record(url, filename)
    parser = Parser.new

    CSV.open(filename, 'wb') do |csv|
      csv << %w[Name Price Image]
    end

    parser.record(url, filename)
  end
end

ProductParserCLI.start(ARGV)
