-- you can run these tests in the browser with elm reactor


module Main exposing (..)

import Html exposing (..)
import String
import Task exposing (Task)
import ElmTest exposing (..)


type alias Person =
    { name : String }


alice : Person
alice =
    Person "Alice"


nameLength : Person -> Int
nameLength =
    .name >> String.length


nameTupleConstructor : Person -> a -> ( String, a )
nameTupleConstructor =
    (,) << .name


andCompose : (a -> b -> c) -> (a -> b) -> a -> c
andCompose f g x =
    f x (g x)


andCompose' :
    (Person -> Int -> ( String, Int ))
    -> (Person -> Int)
    -> Person
    -> ( String, Int )
andCompose' nameTupleConstructor nameLength person =
    nameTupleConstructor person (nameLength person)


(<<*) : (a -> b -> c) -> (a -> b) -> a -> c
(<<*) f g x =
    f x (g x)
infixl 8 <<*


nameWithLength =
    (,)
        << .name
        <<* (String.length << .name)


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
        <<* (.author
                >> (AuthorSummary
                        << .name
                        <<* (String.toUpper << .name)
                   )
            )
    )


construct : b -> a -> b
construct =
    always


from : (a -> b) -> (a -> b -> c) -> (a -> c)
from g f x =
    f x (g x)


transform : (a -> b) -> (b -> c) -> (a -> c -> d) -> (a -> d)
transform g1 g2 f x =
    from (g1 >> g2) f x


summarize' : Note -> NoteSummary
summarize' =
    (construct NoteSummary
        |> from (.content >> String.length)
        |> from (.content >> String.left 50)
        |> transform .author
            (construct AuthorSummary
                |> from .name
                |> from (.name >> String.toUpper)
            )
    )


summarize'' : Note -> NoteSummary
summarize'' { content, author } =
    { characterCount = String.length content
    , excerpt = String.left 50 content
    , author =
        { name = author.name
        , allCapsName = String.toUpper author.name
        }
    }


constructTask =
    Task.succeed


fromTask =
    flip Task.andMap


fetchSomeContent : Task Never String
fetchSomeContent =
    Task.succeed "Hello world!"


fetchSomeAuthor : Task Never Person
fetchSomeAuthor =
    Task.succeed { name = "James" }


fetchNote : Task Never Note
fetchNote =
    constructTask Note
        |> fromTask fetchSomeContent
        |> fromTask fetchSomeAuthor


constructMaybe : a -> Maybe a
constructMaybe =
    Just


fromMaybe : Maybe a -> Maybe (a -> b) -> Maybe b
fromMaybe ma mf =
    case mf of
        Nothing ->
            Nothing

        Just f ->
            Maybe.map f ma


maybeNote : Maybe String -> Maybe Person -> Maybe Note
maybeNote maybeContent maybeAuthor =
    constructMaybe Note
        |> fromMaybe maybeContent
        |> fromMaybe maybeAuthor


tests : Test
tests =
    let
        exampleNote =
            { content = "Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."
            , author =
                { name = "James" }
            }

        expectedNoteSummary =
            { characterCount = 446
            , excerpt = "Lorem ipsum dolor sit amet, consectetur adipisicin"
            , author =
                { name = "James"
                , allCapsName = "JAMES"
                }
            }
    in
        suite "testing most of the stuff in README.md"
            [ test "alice"
                (assertEqual alice.name "Alice")
            , test "nameLength"
                (assertEqual (nameLength alice) 5)
            , test "nameTupleConstructor"
                (assertEqual (nameTupleConstructor alice "some other value") ( "Alice", "some other value" ))
            , test "andCompose"
                (assertEqual
                    (let
                        incrementAndDecrement =
                            ((,) << ((+) 1)) `andCompose` ((+) -1)
                     in
                        incrementAndDecrement 1
                    )
                    ( 2, 0 )
                )
            , test "nameWithLength"
                (assertEqual (nameWithLength alice) ( "Alice", 5 ))
            , test "summarize"
                (assertEqual (summarize exampleNote) expectedNoteSummary)
            , test "summarize'"
                (assertEqual (summarize' exampleNote) expectedNoteSummary)
            , test "summarize''"
                (assertEqual (summarize'' exampleNote) expectedNoteSummary)
            , test "maybeNote with everything present"
                (assertEqual (maybeNote (Just "Hello world!") (Just (Person "James")))
                    (Just (Note "Hello world!" (Person "James")))
                )
            , test "maybeNote with a Nothing"
                (assertEqual (maybeNote (Just "Hello world!") Nothing)
                    Nothing
                )
            ]


main : Program Never
main =
    runSuiteHtml tests
