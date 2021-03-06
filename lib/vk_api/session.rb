# encoding: utf-8
# VK - это небольшая библиотечка на Ruby, позволяющая прозрачно обращаться к API ВКонтакте
# из Ruby.
#
# Author:: Nikolay Karev
# Copyright:: Copyright (c) 2011- Nikolay Karev
# License:: MIT License (http://www.opensource.org/licenses/mit-license.php)
#
# Библиотека VkApi имеет один класс - +::VK:Session+. После создания экземпляра сессии
# вы можете вызывать методы ВКонтакте как будто это методы сессии, например:
#   session = ::VkApi::Session.new app_id, api_access_token
#   session.friends.get :uid => 12
# Такой вызов вернёт вам массив хэшей в виде:
#   # => [{'uid' => '123'}, {:uid => '321'}]

require 'net/http'
require 'uri'
require 'digest/md5'
require 'json'
require 'active_support/inflector'

module VkApi
  # Единственный класс библиотеки, работает как "соединение" с сервером ВКонтакте.
  # Постоянное соединение с сервером не устанавливается, поэтому необходимости в явном
  # отключении от сервера нет.
  # Экземпляр +Session+ может обрабатывать все методы, поддерживаемые API ВКонтакте
  # путём делегирования запросов.
  class Session
    VK_API_URL = 'https://api.vk.com'
    VK_OBJECTS = %w(users friends photos wall audio video places secure language notes pages offers
      questions messages newsfeed status polls subscriptions likes)
    attr_accessor :app_id, :api_access_token

    # Конструктор. Получает следующие аргументы:
    # * app_id: ID приложения ВКонтакте.
    # * api_access_token: access_token, полученный из https://oauth.vk.com/authorize?client_id=##APP_ID##&redirect_uri=http://api.vk.com/blank.html&scope=##PERMISSIONS##&display=page&response_type=token
    def initialize app_id, api_access_token, method_prefix = nil
      unless api_access_token.is_a? String
        raise ArgumentError, 'api_access_token must be a String'
      end
      @app_id, @api_access_token, @prefix = app_id, api_access_token, method_prefix
    end

    # Post request using https
    # from net/http.rb, line 478, modified
    def ssl_post_form(url, params)
      req = Net::HTTP::Post.new(url.request_uri)
      req.form_data = params
      req.basic_auth url.user, url.password if url.user
      http = Net::HTTP.new(url.hostname, url.port)
      http.use_ssl = true
      http.start {|http|
        http.request(req)
      }
    end

    # Выполняет вызов API ВКонтакте
    # * method: Имя метода ВКонтакте, например friends.get
    # * params: Хэш с именованными аргументами метода ВКонтакте
    # Возвращаемое значение: хэш с результатами вызова.
    # Генерируемые исключения: +ServerError+ если сервер ВКонтакте вернул ошибку.
    def call(method, params = {})
      method = method.to_s.camelize(:lower)
      method = @prefix ? "#{@prefix}.#{method}" : method
      params[:access_token] = api_access_token

      # http://vk.com/developers.php?oid=-1&p=%D0%92%D1%8B%D0%BF%D0%BE%D0%BB%D0%BD%D0%B5%D0%BD%D0%B8%D0%B5_%D0%B7%D0%B0%D0%BF%D1%80%D0%BE%D1%81%D0%BE%D0%B2_%D0%BA_API
      # now VK requires the following url: https://api.vk.com/method/METHOD_NAME
      uri = URI.parse(VK_API_URL + "/method/" + method)

      response = JSON.parse(ssl_post_form(uri, params).body)

      raise ServerError.new self, method, params, response['error'] if response['error']
      response['response']
    end

    # Генерирует методы, необходимые для делегирования методов ВКонтакте, так friends,
    # images
    def self.add_method method
      ::VkApi::Session.class_eval do
        define_method method do
          if (! var = instance_variable_get("@#{method}"))
            instance_variable_set("@#{method}", var = ::VkApi::Session.new(app_id, api_access_token, method))
          end
          var
        end
      end
    end

    for method in VK_OBJECTS
      add_method method
    end

    # Перехват неизвестных методов для делегирования серверу ВКонтакте
    def method_missing(name, *args)
      call name, *args
    end

  end

  # Ошибка на серверной стороне
  class ServerError < StandardError
    attr_accessor :session, :method, :params, :error
    def initialize(session, method, params, error)
      super "Server side error calling VK method: #{error}"
      @session, @method, @params, @error = session, method, params, error
    end
  end

end
