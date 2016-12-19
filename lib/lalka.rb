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

      def id(internal)
        internal.on_success { |v| v }
        internal.on_error { |e| e }
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
        Task.id(internal)
      end

      @computation.call(internal)
      queue.pop
    end

    def fork
      internal = InternalAsync.new
      yield internal
      @computation.call(internal)
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
        raise ArgumentError if args.length != 0
        block
      else
        raise ArgumentError if args.length != 1
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
  end

  class InternalAsync < InternalBase
    def resolve(value)
      @on_success.call(value)
    end

    def reject(error)
      @on_error.call(error)
    end
  end

  class Internal < InternalBase
    def initialize(queue)
      @queue = queue
    end

    def resolve(value)
      result = @on_success.call(value)
      @queue.push M.Right(result)
    end

    def reject(error)
      result = @on_error.call(error)
      @queue.push M.Left(result)
    end
  end
end
