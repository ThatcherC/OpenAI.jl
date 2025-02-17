module OpenAI

using Downloads
using JSON3


abstract type AbstractOpenAIProvider end
Base.@kwdef struct OpenAIProvider <: AbstractOpenAIProvider
    api_key::String = ""
    base_url::String = "https://api.openai.com/v1" 
    api_version::String = ""
end
Base.@kwdef struct AzureProvider <: AbstractOpenAIProvider
    api_key::String = ""
    base_url::String = "https://docs-test-001.openai.azure.com/openai/deployments/gpt-35-turbo"
    api_version::String = "2023-03-15-preview"
end

const DEFAULT_PROVIDER = OpenAIProvider();

auth_header(provider::AbstractOpenAIProvider, api_key::AbstractString) = error("auth_header not implemented for $(typeof(provider))")
auth_header(provider::OpenAIProvider, api_key::AbstractString=provider.api_key) = ["Authorization" => "Bearer $(isempty(api_key) ? provider.api_key : api_key)", "Content-Type" => "application/json"]
auth_header(provider::AzureProvider, api_key::AbstractString=provider.api_key) = ["api-key" => (isempty(api_key) ? provider.api_key : api_key), "Content-Type" => "application/json"]

build_url(provider::AbstractOpenAIProvider, api::String) = error("build_url not implemented for $(typeof(provider))")
build_url(provider::OpenAIProvider, api::String) = "$(provider.base_url)/$(api)"
function build_url(provider::AzureProvider, api::String)
    (;base_url, api_version) = provider
    return "$(base_url)/$(api)?api-version=$(api_version)"
end

function build_params(kwargs)
    isempty(kwargs) && return nothing
    buf = IOBuffer()
    JSON3.write(buf, kwargs)
    seekstart(buf)
    return buf
end

function request_body(url; kwargs...)
    resp = nothing
    body = sprint() do output
        resp = request(url; output=output, kwargs...)
    end
    return resp, body
end

function status_error(resp, log=nothing)
    logs = !isnothing(log) ? ": $log" : ""
    error("request status $(resp.message)$logs")
end

function _request(api::AbstractString, provider::AbstractOpenAIProvider, api_key::AbstractString=provider.api_key; method, kwargs...)
    params = build_params(kwargs)
    url = build_url(provider, api)
    resp, body = request_body(url; method, input = params, headers = auth_header(provider, api_key))
    if resp.status >= 400
        status_error(resp, body)
    else
        return OpenAIResponse(resp.status, JSON3.read(body))
    end
end

function openai_request(api::AbstractString, api_key::AbstractString; method, kwargs...)
    global DEFAULT_PROVIDER
    _request(api, DEFAULT_PROVIDER, api_key; method, kwargs...)
end

function openai_request(api::AbstractString, provider::AbstractOpenAIProvider; method, kwargs...)
    _request(api, provider; method, kwargs...)
end

struct OpenAIResponse{R}
    status::Int
    response::R
end

"""
Default model ID for embeddings.
Follows recommendation in OpenAI docs at https://platform.openai.com/docs/models/embeddings.
"""
const DEFAULT_EMBEDDING_MODEL_ID="text-embedding-ada-002"

"""
List models

https://beta.openai.com/docs/api-reference/models/list

# Arguments:
- `api_key::String`: OpenAI API key
"""
function list_models(api_key::String)
    return openai_request("models", api_key; method = "GET")
end

"""
Retrieve model

https://beta.openai.com/docs/api-reference/models/retrieve

# Arguments:
- `api_key::String`: OpenAI API key
- `model_id::String`: Model id
"""
function retrieve_model(api_key::String, model_id::String)
    return openai_request("models/$(model_id)", api_key; method = "GET")
end

"""
Create completion

https://beta.openai.com/docs/api-reference/completions

# Arguments:
- `api_key::String`: OpenAI API key
- `model_id::String`: Model id
"""
function create_completion(api_key::String, model_id::String; kwargs...)
    return openai_request("completions", api_key; method = "POST", model = model_id, kwargs...)
end

"""
Create chat

https://platform.openai.com/docs/api-reference/chat

# Arguments:
- `api_key::String`: OpenAI API key
- `model_id::String`: Model id
- `messages::Vector`: The chat history so far.

## Example:

```julia
julia> CC = create_chat("..........", "gpt-3.5-turbo", 
    [Dict("role" => "user", "content"=> "What is the OpenAI mission?")]
);

julia> CC.response.choices[1][:message][:content]
"\n\nThe OpenAI mission is to create safe and beneficial artificial intelligence (AI) that can help humanity achieve its full potential. The organization aims to discover and develop technical approaches to AI that are safe and aligned with human values. OpenAI believes that AI can help to solve some of the world's most pressing problems, such as climate change, disease, inequality, and poverty. The organization is committed to advancing research and development in AI while ensuring that it is used ethically and responsibly."
```
"""
function create_chat(api_key::String, model_id::String, messages; kwargs...)
    return openai_request("chat/completions", api_key; method = "POST", model = model_id, messages=messages, kwargs...)
end
function create_chat(provider::AbstractOpenAIProvider, model_id::String, messages; kwargs...)
    return openai_request("chat/completions", provider; method = "POST", model = model_id, messages=messages, kwargs...)
end

"""
Create edit

https://beta.openai.com/docs/api-reference/edits/create

# Arguments:
- `api_key::String`: OpenAI API key
- `model_id::String`: Model id (e.g. "text-davinci-edit-001")
- `instruction::String`: The instruction that tells the model how to edit the prompt.
- `input::String` (optional): The input text to use as a starting point for the edit.
- `n::Int` (optional): How many edits to generate for the input and instruction.
"""
function create_edit(api_key::String, model_id::String, instruction::String; kwargs...)
    return openai_request("edits", api_key; method = "POST", model = model_id, instruction, kwargs...)
end

"""
Create embeddings

https://platform.openai.com/docs/api-reference/embeddings

# Arguments:
- `api_key::String`: OpenAI API key
- `input`: The input text to generate the embedding(s) for, as String or array of tokens.
    To get embeddings for multiple inputs in a single request, pass an array of strings
    or array of token arrays. Each input must not exceed 8192 tokens in length.
- `model_id::String`: Model id. Defaults to $DEFAULT_EMBEDDING_MODEL_ID.
"""
function create_embeddings(api_key::String, input, model_id::String=DEFAULT_EMBEDDING_MODEL_ID; kwargs...)
    return openai_request("embeddings", api_key; method = "POST", model = model_id, input, kwargs...)
end

"""
Create images 

https://platform.openai.com/docs/api-reference/images/create

#Arguments: 
- `api_key::String`: OpenAI API key
- `prompt`: The input text to generate the image(s) for, as String or array of tokens.
- `n`::Integer Optional. The number of images to generate. Must be between 1 and 10.
- `size`::String. Optional. Defaults to 1024x1024. The size of the generated images. Must be one of 256x256, 512x512, or 1024x1024.

# once the request is made, 
download like this: 
download(r.response["data"][begin]["url"], "image.png")
"""
function create_images(api_key::String, prompt, n::Integer=1, size::String="256x256"; kwargs...)
    return openai_request("images/generations", api_key; method = "POST", prompt, kwargs...)
end

export OpenAIResponse
export list_models
export retrieve_model
export create_chat
export create_completion
export create_edit
export create_embeddings
export create_images

end # module
