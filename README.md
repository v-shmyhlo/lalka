# Lalka
[![Build Status](https://travis-ci.org/v-shmyhlo/lalka.svg?branch=master)](https://travis-ci.org/v-shmyhlo/lalka)

Lalka is a ruby implementation of a Task monad (aka Continuation monad) - usefull abstraction for managing parallel and concurrent code.

## Usage

### Create:
```ruby
  task = Lalka::Task.new do |t| # block is not executed untill fork or fork_wait is called
    t.resolve(value) # resolve task to a value
    # or
    t.reject(error) # reject task with an error
    # or
    t.try { 100 } # will resolve
    # or
    t.try { raise 'error' } # will reject
  end
```

### Create with predefined state:
```ruby
  resolved_task = Lalka::Task.resolve(value) # task which resolves to a value
  rejected_task = Lalka::Task.reject(error) # task which rejects to a value
  task = Lalka::Task.try { 100 } # will resolve
  task = Lalka::Task.try { raise 'error' } # will reject
```

### fork:
```ruby
  # executes computation, fork is nonblocking, returns nil
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
  # executes computation, fork_wait blocks and returns Either from "dry-monads" gem
  task = Lalka::Task.resolve(100)

  result = task.fork_wait

  result # Right(100)
```

```ruby
  task = Lalka::Task.reject('error')

  result = task.fork_wait

  result # Left("error")
```

### map:
```ruby
  task = Lalka::Task.resolve(99).map { |v| v + 1 }.map { |v| v.to_s + "!" }

  result = task.fork_wait
  result # Right("100!")
```

```ruby
  task = Lalka::Task.reject('error').map { |v| v + 1 }.map { |v| v.to_s + "!" }

  result = task.fork_wait
  result # Left("error")
```

### bind:
```ruby
  task = Lalka::Task.resolve(99).bind { |v| Lalka::Task.resolve(v + 1) }

  result = task.fork_wait
  result # Right(100)
```

### ap:
```ruby
  task = Lalka::Task.resolve(-> (v) { v + 1 }).ap(Lalka::Task.resolve(99))

  result = task.fork_wait
  result # Right(100)
```

```ruby
  task1 = Lalka::Task.resolve(99)
  task2 = Lalka::Task.resolve(1)

  result = task1.map { |x| -> (y) { x + y } }.ap(task2).fork_wait
  result # Right(100)

  result = Lalka::Task.resolve(-> (x) { -> (y) { x + y } }).ap(task1).ap(task2).fork_wait
  result # Right(100)

  result = Lalka::Task.resolve(-> (x, y) { x + y }.curry).ap(task1).ap(task2).fork_wait
  result # Right(100)
```

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'lalka'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install lalka

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/v-shmyhlo/lalka. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
