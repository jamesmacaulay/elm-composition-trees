# A hierarchical data transformation DSL in 3 lines of Elm

_Or: applicative functors are everywhere and they are your friends!_

Suppose we have a simple `Person` type:

```Elm
type alias Person = { name : String }

alice : Person
alice = Person "Alice"
-- { name = "Alice" }
```

With this code, [Elm](http://elm-lang.org/) gives us a special `.name` function that extracts the `name` field from a `Person`, and a `Person` constructor function that makes a `Person` from a name (if the `Person` type had other fields, then the `Person` constructor would take multiple arguments). Suppose we want to concisely define a function that gives us the length of the `name` of a `Person`. Here's how we'd do it with function composition:

```Elm
import String

nameLength : Person -> Int
nameLength = String.length << .name
nameLength alice
-- 5
```

The `<<` operator chains together functions, returning a new function that passes the return value of one function into the argument of the next. Here's its definition:

```Elm
(<<) : (b -> c) -> (a -> b) -> (a -> c)
(<<) g f x =
  g (f x)
```

If we want to compose left-to-right, we can use the `>>` operator instead:

```Elm
nameLength' = .name >> String.length
nameLength' alice
-- 5
```

Function composition can come in handy in a lot of situations. Here it is being used to easily extract nested fields from records:

```Elm
avatarURLs = articles |> List.map (.author >> .avatar >> .url)
```

## The limits of linear composition

Once you get comfortable using these composition operators, after a while you might notice that they have an important limitation: they only feed values into the _first_ argument of any function. Imagine we want to compose a function that takes our `Person` and produces a tuple of both its `.name` and its `nameLength`. For `alice`, the return value of this function would be `("Alice", 5)`. If we weren't trying to use the composition operators, the function would look like this:

```Elm
nameWithLength : Person -> ( String, Int )
nameWithLength person = (person.name, String.length person.name)
```

There's nothing wrong with this, and in many cases it would be the clearest way of defining such a function. But functions like this are often only used once within the body of another function, and often defined using anonymous function syntax. Using the composition operators can be a great way of reducing the "clutter" of argument names and guiding the reader to focus more on how data flows through the program.

In this case we know that since the result is a 2-tuple, we'll somehow need to compose the 2-tuple constructor function `(,)` with _both_ the `.name` and `nameLength` functions, feeding their return values into the first and second arguments of `(,)` respectively. So we'd like to be able to write something like the following, but it doesn't work:

```Elm
nameWithLength = (,) << .name << nameLength
-- TYPE MISMATCH
```

The compiler won't let us do this, because it doesn't really mean what we want it to mean. We want to feed the `Int` result of `nameLength` into the second argument of `(,)`, but it's being fed into the `.name` function instead, which expects a record with a `name` field.  The problem is that `<<` and `>>` can only define linear compositions; they can't build up a tree of functions feeding into other functions that combine their results. So how do we do that? Let's ignore `nameLength` for the time being. It turns out we can compose together `(,)` and `.name` to get something useful:

```Elm
nameTupleConstructor : Person -> a -> ( String, a )
nameTupleConstructor = (,) << .name
```

The `nameTupleConstructor` function takes a `Person` as its first argument, and a value of any other type `a` as its second argument, and returns a tuple of the `name` of the `Person` together with whatever `a` value was supplied. Because Elm functions are curried, this is the same as saying that `nameTupleConstructor` takes a `Person` and _returns a partially applied tuple constructor function_. In other words, the following three definitions are all equivalent:

```Elm
nameTupleConstructor = (,) << .name
nameTupleConstructor person = (,) person.name
nameTupleConstructor person x = (person.name, x)
```

What can we do with this? Well, we want a way of taking this function and composing it with `nameLength` in a way that feeds the result of the `nameLength` function into the _second_ argument of the `nameTupleConstructor` function. Meanwhile, the original `Person` that we gave to `nameLength` needs to also be fed into the _first_ argument of `nameTupleConstructor`:

```Elm
andCompose : (a -> b -> c) -> (a -> b) -> a -> c
andCompose f g x = f x (g x)
-- equivalent to:
-- andCompose f g = (\x -> f x (g x))
```

With this new function, we can plug in `nameTupleConstructor` as the first argument and `nameLength` as the second argument. Then we get a function of one argument returned, which takes a `Person` and returns the appropriate `(String, Int)` tuple. Here's the same definition with the variables renamed and types narrowed to better show what's happening:

```Elm
andCompose' : (Person -> Int -> (String, Int)) -> (Person -> Int) -> Person -> (String, Int)
andCompose' nameTupleConstructor nameLength person =
  nameTupleConstructor person (nameLength person)
```

Using this weird new composition function (and infix backticks for readability), we can define our `nameWithLength` function like so:

```Elm
nameWithLength = ((,) << .name) `andCompose` nameLength
nameWithLength alice
-- ("Alice",5)
```

## Working toward an ergonomic interface

Defining new operators is not something to be taken lightly...but let's throw caution to the wind! Since we're already writing `<<` to compose stuff, `andCompose` just seems clunky.

```Elm
(<<*) : (a -> b -> c) -> (a -> b) -> a -> c
(<<*) f g x = f x (g x)

infixl 8 <<*
```

If you imagine the asterisk in this operator saying "I supply an extra argument!" then you can write `nameWithLength` like this:

```Elm
nameWithLength = (,) << .name <<* nameLength
```

...or perhaps more like this:

```Elm
nameWithLength =
  (,)
    << .name
    <<* (String.length << .name)
```

Cool! If you have combining functions that take more than two arguments, you just chain however many `<<*` expressions on there as you need. Here it is gathering up extra arguments for some record constructor functions:

```Elm
type alias Note =
  { content : String
  , author : Person
  }

type alias NoteSummary =
  { characterCount : Int
  , excerpt : String
  , author : AuthorSummary
  }

type alias AuthorSummary =
  { name : String
  , allCapsName : String
  }

summarize : Note -> NoteSummary
summarize =
  (NoteSummary
    << (String.length << .content)
    <<* (String.left 50 << .content)
    <<*
      (.author
        >>
          (AuthorSummary
            << .name
            <<* (String.toUpper << .name))))
```

Hmm. The new `<<*` operator might be great for small compositions like `nameWithLength`, but once we start making larger compositions it can become a little hard to follow. Also, it's kind of weird that we're using `<<` to feed into the first argument and `<<*` for every other argument...what's so special about the first argument? It would be nice if we could treat all arguments the same way. Also, Elm's `|>` "pipeline" operator is really quite pleasant to read and write...why don't we make a pipeline interface?

Okay, **here is our 3-line data transformation DSL**<sup><a name="footnote-1-ref" href="#footnote-1"><sup>1</a></sup>:

```Elm
construct = always
from g f x = f x (g x)
transform g1 g2 f x = from (g1 >> g2) f x
```

The `construct` function is simple, it just lets us "wrap something in a function" – the implementation is Elm's built-in `always` function, which returns a function that completely ignores its first argument and always returns the wrapped value. We're calling it `construct` because we're going to use it to wrap our multi-argument combining functions, which will incrementally construct a return value as they get fed arguments by our source functions.

The `from` function is just our old `<<*` operator with its arguments flipped. We could have implemented it as `flip (<<*)`. We flip the arguments so that it plays nice with `|>`.

The `transform` function is just sugar for certain kinds of nested compositions – it works like `from` but takes two "source" functions that are composed together before being composed with `from`.

In addition to these three new functions, we'll keep on using `<<` or `>>` whenever we just want straight up composition:

```Elm
summarize' : Note -> NoteSummary
summarize' =
  (construct NoteSummary
    |> from (.content >> String.length)
    |> from (.content >> String.left 50)
    |> transform .author
      (construct AuthorSummary
        |> from .name
        |> from (.name >> String.toUpper)))
```

This looks pretty good! But...okay, let's get real. Even with our nice DSL, in most cases it would be more clear to write a function like this the old fashioned way:

```Elm
summarize'' : Note -> NoteSummary
summarize'' {content, author} =
  { characterCount = String.length content
  , excerpt = String.left 50 content
  , author =
    { name = author.name
    , allCapsName = String.toUpper author.name
    }
  }
```

There are surely _some_ cases where `construct`/`from`/`transform` could clean up a big messy record factory function in a nice way that's worth being a little indirect, but those situations are few and far between. So why go to all this trouble?

## A ubiquitous pattern

The same properties of Elm's type system that allow for this kind of composition _also_ let us hierarchically compose many other things besides functions. For example, Elm's `Task` module provides the `map` and `andMap` functions that are direct analogs to `<<` and our new `<<*` operator, except they compose Tasks instead of functions. Here they are being used to similarly "feed in" the results of multiple Tasks into a single combining function:

```Elm
-- we use `Never` for the error type because this is a contrived example
fetchSomeContent : Task Never String
fetchSomeContent = Task.succeed "Hello world!"

fetchSomeAuthor : Task Never Person
fetchSomeAuthor = Task.succeed { name = "James" }

fetchNote : Task Never Note
fetchNote =
  Note
    `Task.map` fetchSomeContent
    `Task.andMap` fetchSomeAuthor
```

Notice how similar this is to how we were using `<<` and `<<*`. Maybe it isn't so weird to think of composing functions with `<<` as "mapping" one function over another?

Because it's basically the same thing, it's easy to define a `Task` version of our little DSL:

```Elm
constructTask = Task.succeed
fromTask = flip Task.andMap

fetchNote : Task Never Note
fetchNote =
  constructTask Note
    |> fromTask fetchSomeContent
    |> fromTask fetchSomeAuthor
```

Now take a look at how the type signatures of the `construct` and `from` functions compare with these new Task-based equivalents. I've done kind of a funny thing with `type alias` to help make things more clear, but it doesn't change any of the semantics:

```Elm
-- construct : b -> a -> b
-- from : (a -> b) -> (a -> b -> c) -> a -> c
type alias Function a b = a -> b
construct : b -> Function a b
from : Function a b -> Function a (b -> c) -> Function a c

constructTask : b -> Task a b
fromTask : Task a b -> Task a (b -> c) -> Task a c
```

They're the same thing! Here's an implementation for `Maybe`:

```Elm
constructMaybe : a -> Maybe a
constructMaybe = Just

fromMaybe : Maybe a -> Maybe (a -> b) -> Maybe b
fromMaybe ma mf =
  case mf of
    Nothing -> Nothing
    Just f -> Maybe.map f ma

maybeNote : Maybe String -> Maybe Person -> Maybe Note
maybeNote maybeContent maybeAuthor =
  constructMaybe Note
    |> fromMaybe maybeContent
    |> fromMaybe maybeAuthor
```

Similar to `Task` composition, `Maybe` composition "bails out" if anything "goes wrong". With Tasks, that means the first error value encountered gets propagated unchanged to the top-level result. With Maybes, `Nothing` values bubble up to the top in the same way.

Also notice how we can still write sensible versions of these functions even though `Maybe a` has only one type parameter, while `Task a b` and `Function a b` each have two. Even with this difference, the pattern is still easily recognizable in both the types and the composition of values.

The most important thing that all of these implementations share is this: a way to apply functions that are wrapped up in some parameterized type to other kinds of values that are wrapped up in the same way. In the case of function composition, the "wrapper" is a function that returns values of the wrapped type. In the case of `Maybe` composition, the wrapper is `Just`...unless it's `Nothing`, in which case the wrapper is empty and we can't really do anything except return `Nothing` for the whole composition.

You can do the same thing with [`Json.Decode`](https://gist.github.com/jamesmacaulay/c2badacb93b091489dd4), and with not much more code you can build [a _really_ nice pipeline-style JSON decoding interface](http://package.elm-lang.org/packages/NoRedInk/elm-decode-pipeline/1.1.2/).

## It has a name

If you can write an implementation of this pattern for a type, following [a few rules that I haven't gotten into here](https://hackage.haskell.org/package/base-4.9.0.0/docs/Control-Applicative.html#t:Applicative)<sup><a name="footnote-2-ref" href="#footnote-2">2</a></sup>, then we say that the type is an **applicative functor**<sup><a name="footnote-3-ref" href="#footnote-3">3</a></sup>. It's "applicative" because it lets us _apply_ wrapped functions to wrapped arguments. The applicative functor is pretty young as far as computer science concepts go – it was first given a name and precise definition in 2008's [Applicative Programming with Effects](http://www.staff.city.ac.uk/~ross/papers/Applicative.html).

Somehow I keep being surprised by how often applicative functors show up to save the day. They are all over the place! What's cool is that every time I get surprised by one, I end up understanding them in a new way. Over time I've noticed a few kinds of recurring situations that I now use as cues to help me realize what's going on sooner:

* when I feel like I want to iterate over the fields of a record for some reason, or
* when there are different versions of the same function just to deal with different numbers of arguments (e.g. `Json.Decode.object2`, `Json.Decode.object3`, etc.), or
* when I'm struggling to compose some kind of tree that has different types at every branch,

...I should look around for an applicative functor hiding in plain sight.

## Further reading

Most of the information you'll find on applicative functors will be from the world of [Haskell](https://www.haskell.org/). Thankfully Elm and Haskell are very similar languages and have an almost identical syntax, which makes it pretty easy to read most of the examples you'll find if you're already comfortable with Elm.

If you want to get a deeper understanding of functional patterns like this and many others, I can think of no better resource than [Haskell Programming from First Principles](http://haskellbook.com/). It costs some money, but it is one of the best programming books I've ever read. If you want something you can access for free, there's [the Applicative Functor chapter](http://learnyouahaskell.com/functors-applicative-functors-and-monoids#applicative-functors) of [Learn You a Haskell](http://learnyouahaskell.com) (which you can also [pay for](https://www.nostarch.com/lyah.htm)).

_James MacAulay | July 2016_

_https://twitter.com/jamesmacaulay_

<a name="footnote-1" href="#footnote-1-ref">1</a>: I guess our "domain" is "composing functions" ¯\\\_(ツ)\_/¯

<a name="footnote-2" href="#footnote-2-ref">2</a>: In Haskell, the functions and operators associated with applicative functors have different names: `pure` is what this document calls `construct`, `fmap` is `map`, and `<*>` is `andMap`/`<<*`.

<a name="footnote-3" href="#footnote-3-ref">3</a>: In order to merely be a **functor**, a type only requires an implementation of the `map` function.
