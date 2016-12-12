# Usage

### Create:
```ruby
  task = Lalka::Task.new do |t| # block is not executed untill fork or fork_wait is called
    t.resolve(value) # resolve task to a value
    # or
    t.reject(error) # reject task with an error
  end
```

### Create with predefined state:
```ruby
  resolved_task = Lalka::Task.resolve(value) # task which resolves to a value
  rejected_task = Lalka::Task.reject(error) # task which rejects to a value
```

### fork:
```ruby
  # fork is nonblocking, returns nil
  task.fork do |t|
    t.on_success do |value|
      # do something with a value
    end

    t.on_error do |error|
      # handle error
    end
  end
```

### fork_wait:
```ruby
  # fork_wait blocks and returns Either from "dry-monads" gem
  task = Lalka::Task.resolve(99)

  result = task.fork_wait do |t|
    t.on_success do |value|
      value + 1
    end

    t.on_error do |error|
      # ...
    end
  end

  result # Right(100)
```

```ruby
  task = Lalka::Task.reject('error')

  result = task.fork_wait do |t|
    t.on_success do |value|
      # ...
    end

    t.on_error do |error|
      "Error: " + error
    end
  end

  result # Left("Error: error")
```

# Lalka

Welcome to your new gem! In this directory, you'll find the files you need to be able to package up your Ruby library into a gem. Put your Ruby code in the file `lib/lalka`. To experiment with that code, run `bin/console` for an interactive prompt.

TODO: Delete this and the text above, and describe your gem

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'lalka'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install lalka

## Usage

TODO: Write usage instructions here

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/lalka. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

