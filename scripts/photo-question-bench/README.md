# Synthetic photographs for `photo-question-bench.mjs`

Generated for the bench on 29 Sep 2026. None of them is a photograph: nobody
in them exists, and none was taken from a family's album, a museum or Apple's
sample images. Each JPEG is exactly what the model returned, not edited or
recompressed.

- **Model:** `black-forest-labs/FLUX-2-dev` through DeepInfra's
  OpenAI-compatible `POST /v1/openai/images/generations`, `size` `1024x768`,
  `n` 1. Listed at 1 US cent an image.
- **Why these three:** each shows people doing something visible, which is what
  a rule 8 question asks about. The bench tells about all three with the teller
  in the photograph but not saying which person they are, about the steps with
  the teller saying which one, and about the jetty with the teller not in it.

## `cousins-steps.jpg`

> A faded amateur colour snapshot from the 1960s, as a family would have
> printed it. Three young children sit side by side on the wooden front steps
> of a red-painted Finnish farmhouse on a summer day. The small boy in the
> middle raises one hand up beside his face with exactly three fingers held up,
> showing the camera his age. The girl on the left wears a striped cotton dress
> and has a ribbon in her hair. The boy on the right is holding a small brown
> dog on his lap. A tin watering can stands beside the steps. Slightly soft
> focus, warm faded colours, a thin white print border. Ordinary candid family
> photograph, not posed in a studio. Fictional people.

The model drew the middle boy's whole hand raised, not three fingers. The
picture was kept: the bench needs an unnamed person doing something visible,
and a raised hand is that.

## `jetty-rowboat.jpg`

> A grainy black-and-white amateur photograph from the 1950s with a white
> deckled print border. Three adults stand on a narrow wooden jetty on a
> Finnish lake in summer: a woman on the left in a headscarf holding a fishing
> rod, a man in the middle in a flat cap and rolled-up shirt sleeves, and a
> woman on the right carrying an enamel coffee pot. A wooden rowing boat is
> tied to the end of the jetty, and birch trees and a small log sauna stand on
> the shore behind them. Slightly faded, ordinary family snapshot, fictional
> people.

## `birthday-table.jpg`

> A faded amateur colour photograph from the 1970s, taken with a flash in a
> small Finnish kitchen. Four people sit around a table with a checked
> oilcloth: a girl of about eight is blowing out the candles on a strawberry
> cream cake, a woman in a flowered apron is pouring coffee from a pot, a man
> with thick-rimmed glasses is laughing, and a teenage boy in a knitted jumper
> is holding a wrapped present. A rag rug on the floor and a wood-burning stove
> in the corner. Warm orange colour cast, slightly overexposed faces from the
> flash, rounded print corners. Ordinary family snapshot, fictional people.
