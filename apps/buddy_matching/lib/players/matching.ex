defmodule BuddyMatching.Players.Matching do
  @moduledoc """
  Module containing all logic for matching players with other players.
  This included handling whether or not they can play with eachother based on Riot's
  own rules on the matter:
    https://support.riotgames.com/hc/en-us/articles/204010760-Ranked-Play-FAQ
  and whether Players criterias' are mutually compatible.
  """
  alias BuddyMatching.Players.Player
  alias BuddyMatching.Players.Criteria

  @loose_tiers ["UNRANKED", "BRONZE", "SILVER", "GOLD", "PLATINUM"]

  @doc """
  Returns a boolean representing whether Player 'player' and Player 'candidate'
  are able to play together and fit eachother's criteria.

  ## Examples
      iex> diamond1 = %{type: "RANKED_SOLO_5x5", tier: "DIAMOND", rank: 1}
      iex> criteria1 = %Criteria{positions: [:top, :support], voice: [false, true], age_groups: [1]}
      iex> criteria2 = %Criteria{positions: [:marksman, :top], voice: [false], age_groups: [1]}
      iex> player = %Player{id: 1, name: "Lethly", region: :euw, voice: [false],
        languages: ["danish"], age_group: 1, positions: [:marksman],
        leagues: diamond1, champions: ["Vayne", "Caitlyn", "Ezreal"],
        criteria: criteria1, comment: "Great player, promise"}
      iex> candidate = %Player{id: 2, name: "hansp", region: :euw, voice: [false],
        languages: ["danish", "english"], age_group: 1, positions: [:top],
        leagues: diamond1, champions: ["Cho'Gath", "Renekton", "Riven"],
        criteria: criteria2, comment: "Ok player, promise"}
      iex> BuddyMatching.Players.Matching.match?(player, candidate)
      true
  """
  def match?(%Player{} = player, %Player{} = candidate) do
    (lists_intersect?(player.languages, candidate.languages) ||
       (player.criteria.ignore_language && candidate.criteria.ignore_language)) &&
      player.id != candidate.id && can_queue?(player, candidate) &&
      criteria_compatible?(player.criteria, candidate) &&
      criteria_compatible?(candidate.criteria, player)
  end

  # convert two lists to MapSets and see if they intersect?
  defp lists_intersect?(a, b) do
    !MapSet.disjoint?(MapSet.new(a), MapSet.new(b))
  end

  # helper for extracting solo queue and determining if it is possible for
  # two players to queue together
  defp can_queue?(%Player{} = player, %Player{} = candidate) do
    case player.region == candidate.region do
      false -> false
      _ -> tier_compatible?(player.leagues, candidate.leagues)
    end
  end

  @doc """
  Returns a boolean representing whether the Player 'player'
  conforms to the Criteria 'criteria'

  ## Examples
      iex> diamond1 = %{type: "RANKED_SOLO_5x5", tier: "DIAMOND", rank: 1}
      iex> criteria = %Criteria{positions: [:marksman], voice: [false], age_groups: [1]}
      iex> player = %Player{id: 1, name: "Lethly", region: :euw, voice: [false],
        languages: ["danish"], age_group: 1, positions: [:marksman],
        leagues: diamond1, champions: ["Vayne", "Caitlyn", "Ezreal"],
        criteria: criteria, comment: "Fantastic player"}
      iex> BuddyMatching.Players.Matching.criteria_compatible?(criteria, player)
      true
  """
  def criteria_compatible?(%Criteria{} = criteria, %Player{} = player) do
    lists_intersect?(criteria.voice, player.voice) &&
      lists_intersect?(criteria.positions, player.positions) &&
      Enum.member?(criteria.age_groups, player.age_group)
  end

  # This function assumes high isn't in @loose_tiers and that
  # high and low are at most 1 league apart. This should be and is handled
  # in tier_compatible?/2.
  #
  # Defined according to below
  # https://support.riotgames.com/hc/en-us/articles/204010760-Ranked-Play-FAQ
  # Helper for handling special restrictions for cases
  # when the players queuing have a tier discrepancy of 1
  defp rank_compatible?(%{tier: ht} = high, %{tier: lt} = low) do
    hr = get_rank(high)
    lr = get_rank(low)

    cond do
      # master and challenger have equal restrictions
      ht == "MASTER" || ht == "CHALLENGER" ->
        lr in 1..3

      # now we may can assume ht is diamond
      # we also know if hr is diamond, lt has to be platinum
      hr == 1 ->
        ht == lt && lr in 1..4

      # d2 can't queue with plat (shouldn't happen tho)
      hr == 2 ->
        false

      # d3 can queue with plat 1
      hr == 3 ->
        lr == 1

      # d4 can queue with plat 1/2
      hr == 4 ->
        lr in 1..2

      # d5 can queue with plat 1..3
      hr == 5 ->
        lr in 1..3
    end
  end

  @doc """
  Returns a boolean indicating whether the given leagues are able to queue together.

  ## Examples
      iex> league1 = {type: "RANKED_SOLO_5x5", tier: "GOLD", rank: 1}
      iex> league2 = {type: "RANKED_SOLO_5x5", tier: "GOLD", rank: 2}
      iex> BuddyMatching.Players.Matching.tier_compatible?(league1, league2)
      true

      iex> league3 = {type: "RANKED_SOLO_5x5", tier: "DIAMOND", rank: 1}
      iex> league4 = {type: "RANKED_SOLO_5x5", tier: "GOLD", rank: 2}
      iex> BuddyMatching.Players.Matching.tier_compatible?(league3, league4)
      false
  """
  def tier_compatible?(league1, league2) do
    {h, l} = sort_leagues(league1, league2)
    tier_diff = tier_to_int(h.tier) - tier_to_int(l.tier)

    cond do
      # special handling for d1 as it cannot queue with its entire league
      h.tier == "DIAMOND" && get_rank(h) == 1 ->
        rank_compatible?(h, l)

      tier_diff == 0 ->
        true

      tier_diff == 1 ->
        if h.tier in @loose_tiers, do: true, else: rank_compatible?(h, l)

      true ->
        false
    end
  end

  @doc """
  Returns the input sorted as a tuple {high, low}
  If they are equal, league1 is returned as highest

  ## Examples
      iex> league1 = {type: "RANKED_SOLO_5x5", tier: "GOLD", rank: 1}
      iex> league2 = {type: "RANKED_SOLO_5x5", tier: "GOLD", rank: 2}
      iex> BuddyMatching.Players.Matching.sort_leagues(league1, league2)
      {league1, league2}
  """
  def sort_leagues(league1, league2) do
    tier1 = tier_to_int(league1.tier)
    tier2 = tier_to_int(league2.tier)

    cond do
      tier1 > tier2 ->
        {league1, league2}

      tier2 > tier1 ->
        {league2, league1}

      true ->
        if league1.rank <= league2.rank,
          do: {league1, league2},
          else: {league2, league1}
    end
  end

  defp tier_to_int(tier) do
    case tier do
      "BRONZE" ->
        1

      # Riot treats unrankeds like silvers
      "UNRANKED" ->
        2

      "SILVER" ->
        2

      "GOLD" ->
        3

      "PLATINUM" ->
        4

      "DIAMOND" ->
        5

      "MASTER" ->
        6

      "CHALLENGER" ->
        6
    end
  end

  # handle players where we don't know their rank
  # but only their league as rank 5
  defp get_rank(%{rank: nil}), do: 5
  defp get_rank(%{rank: rank}), do: rank
end
