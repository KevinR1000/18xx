# frozen_string_literal: true

require_relative 'meta'
require_relative 'entities'
require_relative 'map'

module Engine
  module Game
    module G18Ireland
      class Game < Game::Base
        include_meta(G18Ireland::Meta)
        include G18Ireland::Entities
        include G18Ireland::Map

        CAPITALIZATION = :incremental
        HOME_TOKEN_TIMING = :par
        SELL_BUY_ORDER = :sell_buy
        MUST_BUY_TRAIN = :always

        ASSIGNMENT_TOKENS = {
          'CDSPC' => '/icons/18_ireland/port_token.svg',
          'TASPS' => '/icons/18_ireland/ship_token.svg',
        }.freeze

        # Two lays with one being an upgrade, second tile costs 20
        TILE_LAYS = [
          { lay: true, upgrade: true },
          { lay: :not_if_upgraded, upgrade: false, cost: 20 },
        ].freeze

        DARGAN_TILE_LAYS = [
          { lay: true, upgrade: true },
          { lay: :not_if_upgraded, upgrade: true, cost: 20, upgrade_cost: 30 },
        ].freeze
        CURRENCY_FORMAT_STR = '£%d'

        BANK_CASH = 4000

        CERT_LIMIT = { 3 => 16, 4 => 12, 5 => 10, 6 => 8 }.freeze

        STARTING_CASH = { 3 => 330, 4 => 250, 5 => 200, 6 => 160 }.freeze

        LIMIT_TOKENS_AFTER_MERGER = 3

        GAME_END_CHECK = { bankrupt: :immediate, stock_market: :current_round, bank: :full_or }.freeze

        MARKET = [
          ['', '62', '68', '76', '84', '92', '100p', '110', '122', '134', '148', '170', '196', '225', '260e'],
          ['', '58', '64', '70', '78', '85p', '94', '102', '112', '124', '136', '150', '172', '198'],
          ['', '55', '60', '65', '70p', '78', '86', '95', '104', '114', '125', '138'],
          ['', '50', '55', '60p', '66', '72', '80', '88', '96', '106'],
          ['', '38y', '50p', '55', '60', '66', '72', '80'],
          ['', '30y', '38y', '50', '55', '60'],
          ['', '24y', '30y', '38y', '50'],
          %w[0c 20y 24y 30y 38y],
        ].freeze

        PHASES = [
          {
            name: '2',
            train_limit: 2,
            tiles: [:yellow],
            operating_rounds: 2,
          },
          {
            name: '4',
            on: '4H',
            train_limit: { minor: 2, major: 4 },
            tiles: %i[yellow green],
            operating_rounds: 2,
            status: ['can_buy_companies'],
          },
          {
            name: '6',
            on: '6H',
            train_limit: { minor: 2, major: 3 },
            tiles: %i[yellow green],
            operating_rounds: 2,
            status: ['can_buy_companies'],
          },
          {
            name: '8',
            on: '8H',
            train_limit: { minor: 1, major: 2 },
            tiles: %i[yellow green brown],
            operating_rounds: 2,
          },
          {
            name: '10',
            on: '10H',
            train_limit: { minor: 1, major: 2 },
            tiles: %i[yellow green brown],
            operating_rounds: 2,
          },
          {
            name: 'D',
            on: 'D',
            train_limit: { minor: 1, major: 2 },
            tiles: %i[yellow green brown gray],
            operating_rounds: 2,
          },
        ].freeze

        # The ' trains are the opposite sides of the physical cards which
        # get added into the bankpool when their equivilent rusts
        TRAINS = [
          {
            name: '2H',
            num: 6,
            distance: 2,
            price: 80,
            rusts_on: '4H',
          },
          {
            name: "1H'",
            num: 6,
            distance: 1,
            price: 40,
            rusts_on: '6H',
            reserved: true,
          },
          {
            name: '4H',
            num: 5,
            distance: 4,
            price: 180,
            rusts_on: '8H',
            events: [{ 'type' => 'corporations_can_merge' }],
          },
          {
            name: "2H'",
            num: 5,
            distance: 2,
            price: 90,
            rusts_on: '10H',
            reserved: true,
          },
          {
            name: '6H',
            num: 4,
            distance: 6,
            price: 300,
            rusts_on: '10H',
          },
          {
            name: "3H'",
            num: 4,
            distance: 3,
            price: 150,
            rusts_on: 'D',
            reserved: true,
          },
          {
            name: '8H',
            num: 3,
            distance: 8,
            price: 440,
            events: [{ 'type' => 'minors_cannot_start' }, { 'type' => 'close_companies' }],
          },
          {
            name: '10H',
            num: 2,
            distance: 10,
            price: 550,
            events: [{ 'type' => 'train_trade_allowed' }],
            discount: {
              "3H'" => 150,
              '8H' => 440,
            },
          },
          {
            name: 'D',
            num: 1,
            distance: 99,
            price: 770,
            discount: {
              '8H' => 440,
              '10H' => 550,
            },
          },
        ].freeze

        EVENTS_TEXT = Base::EVENTS_TEXT.merge('corporations_can_merge' => ['Corporations can merge',
                                                                           'Players can vote to merge corporations'],
                                              'minors_cannot_start' => ['Minors cannot start'],
                                              'train_trade_allowed' =>
                                              ['Train trade in allowed',
                                               'Trains can be traded in for face value for more powerful trains'],)
        # Companies guaranteed to be in the game
        PROTECTED_COMPANIES = %w[DAR DK].freeze
        PROTECTED_CORPORATION = 'DKR'
        KEEP_COMPANIES = 5

        # used for laying tokens, running routes, mergers
        def init_graph
          Graph.new(self, skip_track: :narrow)
        end

        def bankruptcy_limit_reached?
          @players.reject(&:bankrupt).one?
        end

        def tile_lays(entity)
          return super if !entity.corporation? || entity.companies.none? { |c| c.id == 'WDE' }

          DARGAN_TILE_LAYS
        end

        def hex_edge_cost(conn)
          conn[:paths].each_cons(2).sum do |a, b|
            a.hex == b.hex ? 0 : 1
          end
        end

        def route_distance(route)
          route.chains.sum { |conn| hex_edge_cost(conn) }
        end

        def route_distance_str(route)
          "#{route_distance(route)}H"
        end

        def check_distance(route, _visits)
          limit = route.train.distance
          distance = route_distance(route)
          raise GameError, "#{distance} is too many hex edges for #{route.train.name} train" if distance > limit
        end

        def tasps_company
          company_by_id('TASPS')
        end

        def cdspc_company
          company_by_id('CDSPC')
        end

        def revenue_for(route, stops)
          revenue = super
          # Bonus for connected narrow gauges directly connected
          # via narrow gauge without being connected to broad gauge.
          revenue += stops.sum do |stop|
            bonus = 0
            nodes = { stop => true }

            stop.walk(skip_track: :broad, tile_type: self.class::TILE_TYPE) do |path, _, _|
              abort = nil
              path.nodes.each do |p_node|
                next if nodes[p_node]

                # only counts if all paths connected to this node is narrow gauge
                nodes[p_node] = true
                if p_node.paths.all? { |p| p.track == :narrow }
                  bonus += p_node.route_revenue(route.phase, route.train)
                else
                  # if not entirely on narrow gauge, abort path walking!
                  abort = :abort
                end
              end
              abort
            end
            bonus
          end

          # Bonus for assignments
          tasps = tasps_company&.id
          revenue += 20 if route.corporation.assigned?(tasps) && (stops.map(&:hex).find { |hex| hex.assigned?(tasps) })
          cdspc = cdspc_company&.id
          revenue += 10 if route.corporation.assigned?(cdspc) && (stops.map(&:hex).find { |hex| hex.assigned?(cdspc) })

          revenue
        end

        def narrow_connected_hexes(corporation)
          compute_narrow(corporation) unless @narrow_connected_hexes[corporation]
          @narrow_connected_hexes[corporation]
        end

        def narrow_connected_paths(corporation)
          compute_narrow(corporation) unless @narrow_connected_paths[corporation]
          @narrow_connected_paths[corporation]
        end

        def compute_narrow(entity)
          # Narrow gauge network is a separate network that is not blocked by tokens
          hexes = Hash.new { |h, k| h[k] = {} }
          paths = {}

          @graph.connected_nodes(entity).keys.each do |node|
            node.walk(skip_track: :broad, tile_type: self.class::TILE_TYPE) do |path, _, _|
              next if paths[path]

              paths[path] = true

              hex = path.hex

              path.exits.each do |edge|
                hexes[hex][edge] = true
                hexes[hex.neighbors[edge]][hex.invert(edge)] = true
              end
            end
          end

          hexes.default = nil
          hexes.transform_values!(&:keys)

          @narrow_connected_hexes[entity] = hexes
          @narrow_connected_paths[entity] = paths
        end

        def clear_narrow_graph
          @narrow_connected_hexes.clear
          @narrow_connected_paths.clear
        end

        def upgrade_cost(old_tile, hex, entity)
          return 0 if hex.tile.paths.all? { |path| path.track == :narrow }

          super
        end

        def tile_uses_broad_rules?(old_tile, tile)
          # Is this tile a 'broad' gauge lay or a 'narrow' gauge lay.
          # Broad gauge lay is if any of the new exits broad gauge?
          old_paths = old_tile.paths
          new_tile_paths = tile.paths
          new_tile_paths.all? { |path| path.track == :broad || old_paths.any? { |p| path <= p } }
        end

        def legal_tile_rotation?(entity, hex, tile)
          # TIM, DR and TDR can lay irrespective of connectivity.
          if !entity.company? || !%w[TIM DR TDR].include?(entity.id)
            corp = entity.corporation
            connection_directions = if tile_uses_broad_rules?(hex.tile, tile)
                                      graph.connected_hexes(corp)[hex]
                                    else
                                      narrow_connected_hexes(corp)[hex] | graph.connected_hexes(corp)[hex]
                                    end
            # Must be connected for the tile to be layable
            return false unless connection_directions
          end

          # All tile exits must match neighboring tiles
          tile.exits.each do |dir|
            next unless (connecting_path = tile.paths.find { |p| p.exits.include?(dir) })
            next unless (neighboring_tile = hex.neighbors[dir]&.tile)

            neighboring_path = neighboring_tile.paths.find { |p| p.exits.include?(Engine::Hex.invert(dir)) }
            return false if neighboring_path && !connecting_path.tracks_match?(neighboring_path)
          end
          true
        end

        def setup_preround
          # Only keep 3 private companies
          remove_companies = @companies.size - self.class::KEEP_COMPANIES

          companies = @companies.reject do |c|
            self.class::PROTECTED_COMPANIES.include?(c.id)
          end

          removed_companies = companies.sort_by! { rand }.take(remove_companies)
          removed = removed_companies.map do |comp|
            @companies.delete(comp)
            comp.close!
            comp.id
          end
          @log << "Removed #{removed.join(',')} companies"
        end

        def setup
          @narrow_connected_hexes = {}
          @narrow_connected_paths = {}

          corporations, @future_corporations = @corporations.partition do |corporation|
            corporation.type == :minor
          end

          @reserved_trains = depot.upcoming.select(&:reserved)
          @all_reserved_trains = @reserved_trains.dup
          @reserved_trains.each { |train| depot.remove_train(train) }

          protect = corporations.find { |c| c.id == PROTECTED_CORPORATION }
          corporations.delete(protect)
          corporations.sort_by! { rand }
          removed_corporation = corporations.first
          @log << "Removed #{removed_corporation.id} corporation"
          close_corporation(removed_corporation)
          corporations.delete(removed_corporation)
          corporations.unshift(protect)

          @corporations = corporations
        end

        def rust(train)
          unless @all_reserved_trains.include?(train)
            new_distance = train.distance / 2
            new_train = @reserved_trains.find { |t| t.distance == new_distance }
            new_train.reserved = false
            @reserved_trains.delete(new_train)
            @depot.reclaim_train(new_train)
            @extra_trains << new_train.name
          end

          super
        end

        def rust_trains!(train, _entity)
          @extra_trains = []
          super
          return if @extra_trains.empty?

          @log << "-- Event: Rusted trains become #{@extra_trains.uniq.join(', ')},"\
          ' and are available from the bank pool'
        end

        def get_par_prices(entity, _corp)
          @game
            .stock_market
            .par_prices
            .select { |p| p.price * 2 <= entity.cash }
        end

        def after_buy_company(player, company, price)
          abilities(company, :shares) do |ability|
            ability.shares.each do |share|
              if share.president
                # DKR is pared at the highest par price below
                corporation = share.corporation
                par_price = price / 2
                share_price = @stock_market.par_prices.find { |sp| sp.price <= par_price }

                @stock_market.set_par(corporation, share_price)
                @share_pool.buy_shares(player, share, exchange: :free)
                # Receives the bid money
                @bank.spend(price, corporation)
                after_par(corporation)
                # And buys a 2 train
                train = @depot.upcoming.first
                buy_train(corporation, train, train.price)
              else
                share_pool.buy_shares(player, share, exchange: :free)
              end
            end
          end
        end

        def close_dkr_if_unpurchased!
          protect = corporations.find { |c| c.id == PROTECTED_CORPORATION }
          return if protect&.owner&.player?

          close_corporation(protect)
        end

        def upgrades_to?(from, to, special = false, selected_company: nil)
          # The Irish Mail
          return true if special && from.color == :blue && to.color == :red

          # Specials must observe existing rules otherwise
          super(from, to, false, selected_company: selected_company)
        end

        def home_token_locations(corporation)
          hexes.select do |hex|
            hex.tile.cities.any? { |city| city.tokenable?(corporation, free: true) }
          end
        end

        def issuable_shares(entity)
          return [] unless entity.corporation?
          return [] unless entity.num_ipo_shares

          # Can only issue 1
          bundles_for_corporation(entity, entity)
            .select { |bundle| @share_pool.fit_in_bank?(bundle) }.take(1)
        end

        def redeemable_shares(entity)
          return [] unless entity.corporation?

          # Can only redeem 1
          bundles_for_corporation(@share_pool, entity).reject { |bundle| entity.cash < bundle.price }.take(1)
        end

        def new_auction_round
          Engine::Round::Auction.new(self, [
            G18Ireland::Step::WaterfallAuction,
          ])
        end

        def stock_round
          Engine::Round::Stock.new(self, [
            Engine::Step::DiscardTrain,
            Engine::Step::Exchange,
            Engine::Step::HomeToken,
            G18Ireland::Step::BuySellParShares,
          ])
        end

        def merger_round
          G18Ireland::Round::Merger.new(self, [
            Engine::Step::DiscardTrain,
            G18Ireland::Step::MergerVote,
            G18Ireland::Step::Merge,
          ], round_num: @round.round_num)
        end

        def operating_round(round_num)
          Engine::Round::Operating.new(self, [
            Engine::Step::Bankrupt,
            G18Ireland::Step::Assign,
            Engine::Step::Exchange,
            Engine::Step::HomeToken,
            G18Ireland::Step::SpecialTrack,
            Engine::Step::BuyCompany,
            G18Ireland::Step::IssueShares,
            G18Ireland::Step::Track,
            Engine::Step::Token,
            Engine::Step::Route,
            G18Ireland::Step::Dividend,
            Engine::Step::DiscardTrain,
            G18Ireland::Step::BuyTrain,
            [Engine::Step::BuyCompany, { blocks: true }],
          ], round_num: round_num)
        end

        def new_or!
          if @round.round_num < @operating_rounds
            new_operating_round(@round.round_num + 1)
          else
            @turn += 1
            or_set_finished
            new_stock_round
          end
        end

        def next_round!
          @round =
            case @round
            when Engine::Round::Stock
              @operating_rounds = @final_operating_rounds || @phase.operating_rounds
              reorder_players
              new_operating_round
            when Engine::Round::Operating
              or_round_finished
              if @round.round_num < @operating_rounds || phase.name.to_i == 2
                new_or!
              else
                @log << "-- #{round_description('Merger', @round.round_num)} --"
                merger_round
              end
            when G18Ireland::Round::Merger
              new_or!
            when init_round.class
              close_dkr_if_unpurchased!
              reorder_players
              new_stock_round
            end
        end

        def event_corporations_can_merge!
          # All the corporations become available, as minors can now merge/convert to corporations
          @corporations.concat(@future_corporations)
          @future_corporations = []
        end

        def event_minors_cannot_start!
          @corporations, removed = @corporations.partition do |corporation|
            corporation.owned_by_player? || corporation.type != :minor
          end

          hexes.each do |hex|
            hex.tile.cities.each do |city|
              city.reservations.reject! { |reservation| removed.include?(reservation) }
            end
          end

          @log << 'Minors can no longer be started' if removed.any?
        end

        def event_train_trade_allowed!; end
      end
    end
  end
end
