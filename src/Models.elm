module Models exposing (..)

import Date

type alias PostId = String

type alias Post = {
    id: PostId,
    created_at: Date.Date,
    title: String,
    content: String,
}

