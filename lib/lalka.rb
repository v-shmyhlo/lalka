# frozen_string_literal: true
require 'dry-monads'

require 'lalka/version'

module Lalka
  M = Dry::Monads
  # TODO: Invalidate resolve and reject at the same time

  class Task
    class << self
      def resolve(value)
        new do |t|
          t.resolve(value)
        end
      end

      def reject(error)
        new do |t|
          t.reject(error)
        end
      end

      def try(&block)
        new do |t|
          t.try(&block)
        end
      end

      alias of resolve
    end

    def initialize(&block)
      @computation = block
    end

    def fork_wait
      queue = Queue.new
      internal = Internal.new(queue)

      if block_given?
        yield internal
      else
        internal.on_success { |v| v }
        internal.on_error { |e| e }
      end

      internal.call(&@computation)
      queue.pop
    end

    def fork
      internal = InternalAsync.new
      yield internal
      internal.call(&@computation)
      nil
    end

    def map(*args, &block)
      block = function_from_arguments(*args, &block)

      Task.new do |t|
        fork do |this|
          this.on_success do |value|
            t.resolve(block.call(value))
          end

          this.on_error do |error|
            t.reject(error)
          end
        end
      end
    end

    def bind(*args, &block)
      block = function_from_arguments(*args, &block)

      Task.new do |t|
        fork do |this|
          this.on_success do |first_value|
            other_task = block.call(first_value)

            other_task.fork do |other|
              other.on_success do |second_value|
                t.resolve(second_value)
              end

              other.on_error do |error|
                t.reject(error)
              end
            end
          end

          this.on_error do |error|
            t.reject(error)
          end
        end
      end
    end

    def ap(other_task)
      Task.new do |t|
        mutex = Mutex.new
        completed = false
        either = M.Right([M.None(), M.None()])

        complete_task = lambda do |&block|
          mutex.synchronize do
            return if completed

            either = block.call(either)

            if either.right?
              (e_fn, e_arg) = either.value

              e_fn.bind { |fn| e_arg.fmap(fn) }.fmap do |value|
                t.resolve(value)
                completed = true
              end
            else
              error = either.value
              t.reject(error)
              completed = true
            end
          end
        end

        fork do |this|
          this.on_success do |fn|
            complete_task.call do |either|
              either.bind { |_, e_arg| M.Right([M.Some(fn), e_arg]) }
            end
          end

          this.on_error do |error|
            complete_task.call do |either|
              either.bind { M.Left(error) }
            end
          end
        end

        other_task.fork do |other|
          other.on_success do |arg|
            complete_task.call do |either|
              either.bind { |e_fn, _| M.Right([e_fn, M.Some(arg)]) }
            end
          end

          other.on_error do |error|
            complete_task.call do |either|
              either.bind { M.Left(error) }
            end
          end
        end
      end
    end

    alias fmap map
    alias chain bind
    alias flat_map bind

    private

    def function_from_arguments(*args, &block)
      if block_given?
        raise ArgumentError, 'both block and function provided' if args.length != 0
        block
      else
        raise ArgumentError, 'no block or function provided' if args.length != 1
        args[0]
      end
    end
  end

  class InternalBase
    def on_success(&block)
      @on_success = block
      nil
    end

    def on_error(&block)
      @on_error = block
      nil
    end

    def try
      resolve(yield)
    rescue => e
      reject(e)
    end

    def call
      yield self
    rescue => e
      reject(e)
    end
  end

  class InternalAsync < InternalBase
    def resolve(value)
      if @on_success.nil?
        reject(ArgumentError.new('missing on_success block'))
      else
        @on_success.call(value)
      end
    end

    def reject(error)
      raise ArgumentError, 'missing on_error block' if @on_error.nil?

      @on_error.call(error)
    end
  end

  class Internal < InternalBase
    def initialize(queue)
      @queue = queue
    end

    def resolve(value)
      if @on_success.nil?
        reject(ArgumentError.new('missing on_success block'))
      else
        result = @on_success.call(value)
        @queue.push M.Right(result)
      end
    end

    def reject(error)
      result =
        if @on_error.nil?
          ArgumentError.new('missing on_error block')
        else
          @on_error.call(error)
        end

      @queue.push M.Left(result)
    end
  end
end
