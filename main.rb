require 'nokogiri'
require 'open-uri'
require 'csv'

def parse_category_page(url)
  sleep(1)
  open_url = URI.open(url)
  final_url = open_url.base_uri.to_s

  # Если финальный URL отличается от исходного, значит, было перенаправление
  return nil if final_url != url

  doc = Nokogiri::HTML(open_url)

  products = []

  # Ищем все товары на странице категории
  doc.xpath('//div[contains(@class, "product-container")]').each do |product|
    product_url = product.xpath('.//a[@class="product_img_link pro_img_hover_scale product-list-category-img"]/@href').text.strip
    products.concat(parse_product_page(product_url))
  end

  products.empty? ? nil : products
end

def parse_product_page(url)
  doc = Nokogiri::HTML(URI.open(url))

  base_name = doc.xpath('//div[@itemtype="http://schema.org/Product"]/meta[@itemprop="name"]/@content').text
  images = doc.xpath('//div[@itemtype="http://schema.org/Product"]/link[@itemprop="image"]/@href')

  variants = []

  # Ищем все варианты продукта на странице продукта
  doc.xpath('//ul[@class="attribute_radio_list pundaline-variations"]/li').each do |variant|
    variant_name = variant.xpath('.//span[@class="radio_label"]').text.strip
    price = variant.xpath('.//span[@class="price_comb"]').text.strip
    name = "#{base_name} - #{variant_name}"

    # Добавляем изображение для каждого варианта продукта
    variants << [name, price, images[0].text]
  end

  variants
end


# Функция для записи данных в CSV файл
def write_to_csv(data, filename, page_number)
  CSV.open(filename, "a") do |csv|
    # csv << ["Name", "Price", "Image"]
    csv << ["Page number: #{page_number}"]
    data.each do |row|
      csv << row
    end
  end
end

def process_category(category_url, filename)
  page_number = 1

  loop do
    all_products = parse_category_page(category_url)

    # Если на странице нет продуктов, значит, мы достигли конца пагинации
    break if all_products.nil?

    write_to_csv(all_products, filename, page_number)

    # Обработка пагинации
    page_number += 1
    category_url = "https://www.petsonic.com/dermatitis-y-problemas-piel-para-perros/?p=#{page_number}"
  end
end

# Пример запуска скрипта
# Сначала создаем заголовок CSV файла
CSV.open("pet_products.csv", "wb") do |csv|
  csv << ["Name", "Price", "Image"]
end

# Затем обрабатываем категорию и записываем данные в CSV файл
process_category("https://www.petsonic.com/dermatitis-y-problemas-piel-para-perros/", "pet_products.csv")
