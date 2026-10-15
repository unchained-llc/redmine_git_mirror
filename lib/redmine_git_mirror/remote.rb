require 'uri'

module RedmineGitMirror
  # Repository identity is independent of transport and the optional .git suffix.
  class Remote
    attr_reader :host, :path

    def initialize(value)
      value = value.to_s.strip
      if value.match?(%r{\A(?:https?|ssh)://})
        uri = URI.parse(value)
        raise ArgumentError if uri.password || (%w[http https].include?(uri.scheme) && uri.userinfo) || uri.query || uri.fragment
        @host, @path = uri.host, uri.path
      elsif (match = value.match(/\A(?:[^@\s]+@)?([a-zA-Z0-9.-]+):([^\s]+)\z/))
        @host, @path = match.captures
      else
        raise ArgumentError
      end
      @host = @host.to_s.downcase
      @path = @path.to_s.sub(%r{\A/}, '').sub(%r{/\z}, '').sub(/\.git\z/, '')
      parts = @path.split('/')
      raise ArgumentError unless !@host.empty? && parts.length >= 2 && parts.all? { |part| part.match?(/\A[a-zA-Z0-9_.-]+\z/) && !%w[. ..].include?(part) }
    rescue URI::InvalidURIError
      raise ArgumentError, 'Invalid repository URL'
    end

    def identity
      "#{host}/#{path}"
    end

    def self.same?(left, right)
      new(left).identity == new(right).identity
    rescue ArgumentError
      false
    end
  end
end
