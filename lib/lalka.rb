# frozen_string_literal: true
require 'lalka/version'
require 'dry-monads'
require 'concurrent'

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
        atom = Concurrent::Atom.new(M.Right(fn: M.None(), arg: M.None()))

        atom.add_observer do |_, _, either|
          if either.right?
            value = either.value

            value[:fn].bind { |fn| value[:arg].fmap(fn) }.fmap do |result|
              t.resolve(result)
              atom.delete_observers
            end
          else
            error = either.value

            t.reject(error)
            atom.delete_observers
          end
        end

        fork do |this|
          this.on_success do |fn|
            atom.swap(fn) { |either, fn| either.bind { |struct| M.Right(struct.merge(fn: M.Some(fn))) } }
          end

          this.on_error do |error|
            atom.swap(error) { |either, error| either.bind { M.Left(error) } }
          end
        end

        other_task.fork do |other|
          other.on_success do |arg|
            atom.swap(arg) { |either, arg| either.bind { |struct| M.Right(struct.merge(arg: M.Some(arg))) } }
          end

          other.on_error do |error|
            atom.swap(error) { |either, error| either.bind { M.Left(error) } }
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
