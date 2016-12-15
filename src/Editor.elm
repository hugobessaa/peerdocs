module Editor exposing (main)

{-| Editor

@docs main
-}

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Diff
import String
import Maybe
import Logoot as L
import List exposing (..)
import Random
import Peer
import Platform.Cmd exposing ((!))


apiKey =
    "qdr1ywu2uofos9k9"


type alias Flags =
    { peer : String
    , location : String
    }


{-| -}
main : Program Flags Model Msg
main =
    Html.programWithFlags
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }



-- Init


init { peer, location } =
    ( { initModel | peer = peer, location = location }
    , Random.generate SetSite (Random.int 1 32000)
    )



-- Model


type alias Model =
    { text : String
    , logoot : L.Logoot String
    , site : L.Site
    , clock : L.Clock
    , id : String
    , peer : String
    , location : String
    }


initModel =
    { text = ""
    , logoot = L.empty ""
    , site = 0
    , clock = 0
    , id = ""
    , peer = ""
    , location = ""
    }



-- Subscriptions


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Peer.subscribe PeerMessage
        ]



-- Update


type Msg
    = SetSite Int
    | ChangeValue String
    | PeerMessage Peer.PeerOperation


update : Msg -> Model -> ( Model, Cmd Msg )
update action model =
    case action of
        SetSite site ->
            setSite site model

        ChangeValue text ->
            changeValue text model

        PeerMessage msg ->
            peerMessage msg model


setSite : Int -> Model -> ( Model, Cmd Msg )
setSite site model =
    let
        id =
            toString site
    in
        ( { model | site = site, id = toString site }
        , Peer.init { id = id, key = apiKey }
        )


peerMessage : Peer.PeerOperation -> Model -> ( Model, Cmd Msg )
peerMessage { id, operation, pid, content } model =
    let
        modify =
            case operation of
                "insert" ->
                    L.insert pid content

                "remove" ->
                    L.remove pid content

                _ ->
                    identity

        newLogoot =
            modify model.logoot
    in
        ( { model
            | logoot = newLogoot
            , text = newLogoot |> L.toList |> List.map Tuple.second |> String.join "\n"
            , peer = id
          }
        , Cmd.none
        )


changeValue : String -> Model -> ( Model, Cmd Msg )
changeValue text model =
    let
        diff =
            Diff.diffLines model.text text

        ( newLogoot, peerOperations, clock ) =
            diff |> changesToOperations |> applyOperations model.site model.clock model.logoot
    in
        { model
            | text = newLogoot |> L.toList |> List.map Tuple.second |> List.drop 1 |> butlast |> String.join "\n"
            , logoot = newLogoot
            , clock = clock
        }
            ! (peerOperations
                |> List.map
                    (\( operation, pid, content ) ->
                        Peer.send
                            { id = model.id
                            , key = apiKey
                            , peerId = model.peer
                            , payload =
                                { id = model.id
                                , operation = operation
                                , pid = pid
                                , content = content
                                }
                            }
                    )
              )


type Operation
    = Insert String
    | Remove String
    | Noop


type alias PeerOperation =
    ( String, L.Pid, String )


changesToOperations : List (Diff.Change String) -> List Operation
changesToOperations =
    List.map changeToOperations


changeToOperations : Diff.Change String -> Operation
changeToOperations change =
    case change of
        Diff.NoChange str ->
            Noop

        Diff.Removed str ->
            Remove str

        Diff.Added str ->
            Insert str


applyOperations : L.Site -> L.Clock -> L.Logoot String -> List Operation -> ( L.Logoot String, List PeerOperation, L.Clock )
applyOperations site clock logoot ops =
    let
        ( _, newLogoot, peerOperations, newClock ) =
            foldl (applyOperation site) ( 0, logoot, [], clock ) ops
    in
        ( newLogoot, peerOperations, newClock )


applyOperation : L.Site -> Operation -> ( Int, L.Logoot String, List PeerOperation, L.Clock ) -> ( Int, L.Logoot String, List PeerOperation, L.Clock )
applyOperation site op ( cursor, logoot, peerOperations, clock ) =
    let
        pidDefault =
            Maybe.withDefault ( [ ( 0, 0 ) ], 0 )

        ( newCursor, newLogoot, newOperations, newClock ) =
            case op of
                Insert str ->
                    let
                        new =
                            (Maybe.withDefault logoot <|
                                L.insertAt site clock cursor str logoot
                            )
                    in
                        ( cursor + 1
                        , new
                        , ( "insert", (pidAtIndex (cursor + 1) new) |> pidDefault, str ) :: peerOperations
                        , clock + 1
                        )

                Remove str ->
                    let
                        pid =
                            (pidAtIndex (cursor + 1) logoot |> pidDefault)

                        new =
                            L.remove pid str logoot
                    in
                        ( cursor
                        , new
                        , ( "remove", pid, str ) :: peerOperations
                        , clock
                        )

                Noop ->
                    ( cursor + 1
                    , logoot
                    , peerOperations
                    , clock
                    )
    in
        ( newCursor, newLogoot, newOperations, newClock )


pidAtIndex : Int -> L.Logoot String -> Maybe L.Pid
pidAtIndex index logoot =
    logoot
        |> L.toList
        |> indexedMap (,)
        |> filter (Tuple.first >> (==) index)
        |> List.map Tuple.second
        |> List.map Tuple.first
        |> head



-- View


editorStyles =
    style
        [ ( "width", "100%" )
        , ( "maxWidth", "650px" )
        , ( "height", "65vh" )
        , ( "padding", "40px 20px 20px" )
        , ( "fontFamily", "inherit" )
        , ( "fontSize", "inherit" )
        , ( "display", "block" )
        , ( "margin", "0 auto" )
        , ( "border", "0" )
        , ( "outline", "none" )
        ]


welcomeStyles =
    style
        [ ( "padding", "20px" )
        , ( "background", "rgb(59, 160, 243)" )
        , ( "color", "white" )
        , ( "textAlign", "center" )
        , ( "minHeight", "35vh" )
        ]


linkStyles =
    style
        [ ( "color", "inherit" )
        , ( "display", "block" )
        , ( "border", "1px dashed" )
        , ( "padding", "10px" )
        , ( "fontSize", "1.5rem" )
        , ( "overflow", "hidden" )
        , ( "textOverflow", "ellipsis" )
        ]


listStyles =
    style
        [ ( "margin", "0" )
        , ( "padding", "0" )
        ]


itemStyles =
    style
        [ ( "display", "block" )
        , ( "padding", "10px" )
        ]


itsOpenStyles =
    style
        [ ( "color", "inherit" ) ]


fire =
    img [ src "/assets/fire.svg", class "emoji fire" ] []


pencil =
    img [ src "/assets/pencil.svg", class "emoji pencil" ] []


view : Model -> Html Msg
view model =
    div []
        [ textarea
            [ editorStyles
            , value model.text
            , placeholder "Write something!"
            , onInput ChangeValue
            , autofocus True
            ]
            []
        , section [ welcomeStyles ]
            [ h1 [] [ text "Welcome to Peerdocs!" ]
            , ol [ listStyles ]
                (if model.peer == "" then
                    connectItems model
                 else
                    connectedItems model
                )
            ]
        ]


connectedItems : Model -> List (Html Msg)
connectedItems model =
    [ li [ itemStyles ]
        [ span []
            [ text <| "Writing with " ++ model.peer
            ]
        ]
    , itsOpenItem
    ]


connectItems : Model -> List (Html Msg)
connectItems model =
    [ li [ itemStyles ]
        [ span []
            [ fire
            , text " Share this with your peers "
            , fire
            ]
        ]
    , li [ itemStyles ]
        [ a [ linkStyles, href (model.location ++ "#" ++ model.id) ]
            [ text (model.location ++ "#" ++ model.id) ]
        ]
    , li [ itemStyles ]
        [ span [] [ text "Write something together!" ]
        ]
    , itsOpenItem
    ]


itsOpenItem : Html Msg
itsOpenItem =
    li [ itemStyles ]
        [ span []
            [ a [ itsOpenStyles, href "https://github.com/hugobessaa/peerdocs" ] [ text "GitHub" ]
            ]
        ]


butlast : List a -> List a
butlast list =
    List.take ((List.length list) - 1) list
